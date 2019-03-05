require "timeout"
require "open3"
require "digest"
require "rack/mime"
require "aws-sdk"
require "mini_exiftool"

##
# An image processing client that uses ImageMagick's convert and an AWS S3-like API for storage.
#
# @example
#
# client = PhotographicMemory.new(@config)
# client.put file: image, id: 123
#
# @param [Hash]    config
# @param [String]  config[:environment]          - The application environment.  Is optional and only changes behavior with the string "test", which stubs S3 responses and prevents calls to Rekognition.
# @param [String]  config[:s3_region]            - The region to use for S3.  Only relevant when actually using AWS S3.
# @param [String]  config[:s3_endpoint]          - The endpoint to use for S3 calls.  Only required when using your own S3-compatible storage medium.
# @param [Boolean] config[:s3_force_path_style]  - Forces path style for S3 API calls.  Defaults to true.
# @param [String]  config[:s3_access_key_id]     - The access key ID for S3 calls.
# @param [String]  config[:s3_secret_access_key] - The secret access key for S3 calls.
# @param [string]  config[:s3_signature_version] - The signature version for S3 calls.  Defaults to 's3'.
# @param [string]  config[:rekognition_access_key_id]     - The access key ID for Rekognition calls.
# @param [string]  config[:rekognition_secret_access_key] - The secret access key for Rekognition calls.
# @param [string]  config[:rekognition_region]            - The region for Rekognition calls.
#
class PhotographicMemory

  attr_accessor :config, :s3_client

  class PhotographicMemoryError < StandardError; end

  def initialize config={}
    @config = config
    options = {
      region:           config[:s3_region],
      endpoint:         config[:s3_endpoint],
      force_path_style: config[:s3_force_path_style] || true,
      credentials: Aws::Credentials.new(
        config[:s3_access_key_id],
        config[:s3_secret_access_key]
      ),
      stub_responses:    config[:environment] === "test",
      signature_version: config[:s3_signature_version] || "s3"
    }.select{|k,v| !v.nil?}
    @s3_client = Aws::S3::Client.new(options)
  end

  def put file:, key:, id:, style_name:"original", convert_options: [], content_type:
    unless (style_name == "original") || convert_options.empty?
      if content_type.match "image/gif"
        output = render_gif file, convert_options
      else
        output = render file, convert_options
      end
    else
      output = file.read
    end
    file.rewind
    original_digest    = Digest::MD5.hexdigest(file.read)
    rendered_digest    = Digest::MD5.hexdigest(output)
    output_fingerprint = (style_name == "original") ? "original" : rendered_digest
    extension          = Rack::Mime::MIME_TYPES.invert[content_type]
    key ||= "#{id}_#{original_digest}_#{output_fingerprint}#{extension}"
    @s3_client.put_object({
      bucket: @config[:s3_bucket],
      key: key,
      body: output,
      content_type: content_type
    })
    if style_name == "original" && config[:environment] != "test"
      reference = StringIO.new render(file, ["-quality 10"])
      # 👆 this is a low quality reference image we generate
      # which is sufficient for classification purposes but
      # saves bandwidth and overcomes the file size limit
      # for Rekognition
      keywords = detect_labels reference
      gravity  = detect_gravity reference
    else
      keywords = []
      gravity  = "Center"
    end
    {
      fingerprint: rendered_digest,
      metadata:    exif(file),
      extension:   extension,
      filename:    key,
      keywords:    keywords,
      gravity:     gravity
    }
  end

  def get key
    @s3_client.get_object({
      bucket: @config[:s3_bucket],
      key: key
    }).body
  end

  def delete key
    @s3_client.delete_object({
      bucket: @config[:s3_bucket],
      key: key
    })
  end

  private

  def exif file
    file.rewind
    MiniExiftool.new(file, :replace_invalid_chars => "")    
  end

  def render file, convert_options=[]
    file.rewind
    run_command ["convert", "-", convert_options, "jpeg:-"].flatten.join(" "), file.read.force_encoding("UTF-8")
  end

  def render_gif file, convert_options=[]
    convert_options.concat(["-coalesce", "-repage 0x0", "+repage"])
    convert_options.each do |option|
      if option.match("-crop")
        option.concat " +repage"
      end
    end
    file.rewind
    run_command ["convert", "-", convert_options, "gif:-"].flatten.join(" "), file.read.force_encoding("UTF-8")
  end

  def classify file
    file.rewind
    detect_labels file
  rescue Aws::Rekognition::Errors::ServiceError, Aws::Errors::MissingRegionError, Seahorse::Client::NetworkingError
    # This also is not worth crashing over
    []
  end

  def detect_gravity file
    file.rewind

    boxes = detect_faces(file).map(&:bounding_box)

    box = boxes.max_by{|b| b.width * b.height } # use the largest face in the photo

    return "Center" if !box

    x = nearest_fifth((box.width / 2)   + ((box.left >= 0) ? box.left : 0))
    y = nearest_fifth((box.height / 2)  + ((box.top  >= 0) ? box.top  : 0))

    gravity_table = {
      0.0 => {
        0.0 => "NorthWest",
        0.5 => "West",
        1.0 => "SouthWest"
      },
      0.5 => {
        0.0 => "North",
        0.5 => "Center",
        1 => "South"
      },
      1.0 => {
        0.0 => "NorthEast",
        0.5 => "East",
        1.0 => "SouthEast"
      }
    }

    gravity_table[x][y]
  end

  def nearest_fifth num
    (num * 2).round / 2.0
  end

  def detect_labels file
    file.rewind
    # get the original image from S3 and classify
    client = Aws::Rekognition::Client.new({
      region: @config[:rekognition_region],
      credentials: Aws::Credentials.new(
        @config[:rekognition_access_key_id],
        @config[:rekognition_secret_access_key]
      )
    })
    client.detect_labels({
      image: {
        bytes: file
      },
      max_labels: 123, 
      min_confidence: 73, 
    }).labels
  rescue Aws::Rekognition::Errors::ServiceError, Aws::Errors::MissingRegionError, Seahorse::Client::NetworkingError => e
    []
  end

  def detect_faces file
    file.rewind
    # get the original image from S3 and classify
    client = Aws::Rekognition::Client.new({
      region: @config[:rekognition_region],
      credentials: Aws::Credentials.new(
        @config[:rekognition_access_key_id],
        @config[:rekognition_secret_access_key]
      )
    })
    client.detect_faces({
      image: {
        bytes: file
      },
      attributes: ["ALL"]
    }).face_details
  rescue Aws::Rekognition::Errors::ServiceError, Aws::Errors::MissingRegionError, Seahorse::Client::NetworkingError => e
    []
  end

  def run_command command, input
    stdin, stdout, stderr, wait_thr = Open3.popen3(command)
    pid = wait_thr.pid

    Timeout.timeout(10) do # cancel in 10 seconds
      stdin.write input
      stdin.close

      output_buffer = []
      error_buffer  = []

      while (output_chunk = stdout.gets) || (error_chunk = stderr.gets)
        output_buffer << output_chunk
        error_buffer  << error_chunk
      end

      output_buffer.compact!
      error_buffer.compact!

      output = output_buffer.any? ? output_buffer.join('') : nil
      error  = error_buffer.any? ? error_buffer.join('') : nil

      unless error
        raise PhotographicMemoryError, "No output received." if !output
      else
        raise PhotographicMemoryError, error
      end
      output
    end
  rescue Timeout::Error, Errno::EPIPE => e
    raise PhotographicMemoryError, e.message
  ensure
    begin
      Process.kill("KILL", pid) if pid
    rescue Errno::ESRCH
      # Process is already dead so do nothing.
    end
    stdin  = nil
    stdout = nil
    stderr = nil
    wait_thr.value if wait_thr # Process::Status object returned.
  end
end

