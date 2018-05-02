require_relative "../lib/photographic_memory"
require "minitest/autorun"
require "fileutils"
require "byebug"

describe PhotographicMemory do
  before do
    @client = PhotographicMemory.new({
      s3_access_key_id:     "xxx",
      s3_secret_access_key: "xxx",
      s3_bucket:            "uploads",
      s3_endpoint:          "http://127.0.0.1:8080/"
    })
  end

  after do
    FileUtils.rm_rf("#{File.dirname(__FILE__)}/../s3-data/uploads")
  end

  describe "#put" do
    it "uploads an jpeg and returns metadata" do
      image  = File.open("#{File.dirname(__FILE__)}/images/landscape.jpg", "r")
      output = @client.put file: image, id: "12345", content_type: "image/jpeg"
      assert output[:fingerprint]
      assert output[:extension]
      assert output[:metadata]
      assert output[:filename]
      assert output[:keywords]
      assert output[:gravity]
    end
    it "renders an image with imagemagick" do
      image  = File.open("#{File.dirname(__FILE__)}/images/landscape.jpg", "r")
      output = @client.put file: image, id: "12345", style_name: "custom", convert_options: ["-resize 25%"], content_type: "image/jpeg"
      file   = @client.get output[:filename]
      assert file.length != 0
      assert file.length < image.size
    end
  end 

  describe "#get" do
    it "returns an uploaded file" do
      image  = File.open("#{File.dirname(__FILE__)}/images/landscape.jpg", "r")
      output = @client.put file: image, id: "12345", content_type: "image/jpeg"
      file   = @client.get output[:filename]
      # byebug
      assert file
    end
    it "errors when no file exists" do
      begin
        @client.get "foobar"
      rescue Aws::S3::Errors::NoSuchKey
        assert true
      end
    end
  end

  describe "#delete" do
    it "removes an uploaded file" do
      image  = File.open("#{File.dirname(__FILE__)}/images/landscape.jpg", "r")
      output = @client.put file: image, id: "12345", content_type: "image/jpeg"
      @client.delete output[:filename]
      begin
        @client.get output[:filename]
      rescue Aws::S3::Errors::NoSuchKey
        assert true
      end
    end
  end

end

