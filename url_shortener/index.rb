# frozen_string_literal: true

require 'aws-sdk-s3'
require 'json'
require 'securerandom'
require 'uri'

BUCKET_NAME = 'your-url-shortener'
BUCKET_WEBSITE_URL = 'https://your-domain'

def handler(event:, context:)
  s3 = Aws::S3::Resource.new
  url_str = event['url']
  return { statusCode: 400, body: 'Invalid url parameter.' } unless valid_url?(url_str)

  loop do
    file_name = SecureRandom.alphanumeric(6)
    obj = s3.bucket(BUCKET_NAME).object(file_name)
    unless file_exists?(obj)
      obj.put(body: '', website_redirect_location: url_str, acl: 'public-read')
      return { statusCode: 200, body: "#{BUCKET_WEBSITE_URL}/#{file_name}" }
    end
  end
end

private

def valid_url?(url_str)
  uri = URI.parse(url_str)
  uri.is_a?(URI::HTTP) && !uri.host.nil?
rescue URI::InvalidURIError
  false
end

def file_exists?(obj)
  obj.get
  true
rescue Aws::S3::Errors::NoSuchKey
  false
end
