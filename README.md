Photographic Memory
===================

Simple image storage and processing for Ruby.

Photographic Memory was extracted out of [KPCC](https://scpr.org/)'s [AssetHost](https://github.com/scpr/assethost), a solution for hosting and serving images for news stories.  It is the core library that handles storage, rendering, and metadata.

## Features

- Simple uniform storage to an S3-compatible API, which of course includes [AWS S3](https://aws.amazon.com/s3/), [Riak CS](https://github.com/basho/riak_cs), and [Fake S3](https://github.com/jubos/fake-s3), among others.  Whether you want storage that's local or in the cloud, we've got you covered.
- Feature classification through [AWS Rekognition](https://aws.amazon.com/rekognition/).
- Image gravity detection(when Rekognition is enabled).  This means that a person's face in a portrait photo shouldn't get cut off when the photo is cropped to landscape.
- Animated GIF support.

## Prerequisites

You must have these installed on the host system:

- Ruby > v2.0.0
- Imagemagick >= 6.0.0
- Exiftool

## Installation

```sh
gem install photographic_memory
```

## Usage

```ruby
config = {
  s3_access_key_id:              ENV["PM_S3_ACCESS_KEY_ID"],
  s3_secret_access_key:          ENV["PM_S3_SECRET_ACCESS_KEY"],
  s3_bucket:                     ENV["PM_S3_BUCKET"],
  rekognition_access_key_id:     ENV["PM_REKOGNITION_ACCESS_KEY_ID"],
  rekognition_secret_access_key: ENV["PM_REKOGNITION_SECRET_ACCESS_KEY"],
}

client  = PhotographicMemory.new(config)

file    = File.new("some_image.jpg", "r")

image_id = "12345"

options = ["-quality 95", "-scale 640x480", "-crop 100x100+0+0"]

data    = uploader.put file: file, id: image_id, convert_options: options, content_type: "image/jpeg"

output  = uploader.get data.filename

uploader.delete data.filename
```

## Testing

The tests use [Minitest](https://github.com/seattlerb/minitest).

There is a Docker Compose file provided that you can use to run a dummy S3 API.  Be sure this is running before running the test with `docker-compose up -d`.

Then simply run `rake test` to perform the tests.

## License

See [LICENSE.txt](LICENSE.txt).

