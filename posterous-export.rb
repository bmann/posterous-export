#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'net/http'

require 'posterous'
Posterous.config = {
  'username'  => 'nancibonfim',
  'password'  => 'nanciposter0us_export'
}

include Posterous

POSTEROUS_URL = "http://posterous.com/api/2/"
SITE = "sites/"
PUBLIC_POSTS = "/posts/public"

#debug
require 'pp'

# little wrapper to the fecth method
def call_api(*args)
  fetch(POSTEROUS_URL + args.join)
end

# little API wrapper
def public_posts(site)
  call_api(SITE, site, PUBLIC_POSTS)
end

# fetch method based on the Net::HTTP documentation
def fetch(uri_str, limit = 10)
  raise ArgumentError, 'too many HTTP redirects' if limit == 0

  response = Net::HTTP.get_response(URI(uri_str))

  case response
  when Net::HTTPSuccess then
    response
  when Net::HTTPRedirection then
    fetch(response['location'], limit - 1)
  else
    response.value
  end
end

# Error class for not implemented methods
class NotImplementedException < StandardError
end

# Class to hold the post information
class Post
  attr_reader :title, :slug, :date, :body, :comments, :tags, :images, :videos,  :audio_files

  def initialize(data=nil)
    @body = ""

    parse_data(data) unless data.nil?
  end

  def parse_data(data)
    @body = data["body_full"]
    @title = data["title"]
    @slug = data["slug"]
    @date = data["display_date"]
    # TODO: test with a post with comments
    @comments = data["comments"]
    @tags = data["tags"].map {|tag| tag["name"] } unless data["tags"].nil?
    # TODO: test with a post with multiple images
    @images = data["media"]["images"].map {|image| image.values.map{|value| value["url"] } }[0] || Array.new

    # TODO: test with audio files and videos
    @audio_files = data["media"]["audio_files"]
    @videos = data["media"]["videos"]
  end

  def fetch_images
    #stub
    raise NotImplementedException
  end

  def fetch_audio
    #stub
    raise NotImplementedException
  end

  def fetch_videos
    #stub
    raise NotImplementedException
  end

  def convert
    #stub
    raise NotImplementedException
  end

  def save
    #stub
    raise NotImplementedException
  end

  def fetch_media
    fetch_images
    fetch_videos
    fetch_audio
  end

end

def main
  posts = nil

  begin
    # TODO: wait until get the token for the Posterous API and update this

    # try to authenticate using posterous gem
    @user = User.me
    pp @user

    pp "Posts: #{@user.posts}"

    @site = Site.find("markdownexport")

    pp @site

    pp "Posts from markdownexport: #{@site.posts}"
  rescue Posterous::Connection::ConnectionError
    # fail back to unauthenticated access
    res = public_posts("markdownexport")
    ruby_data = JSON.parse(res.body)
    posts = ruby_data.map {|entry| Post.new(entry) }
  end

  pp posts

  # posts.convert
  # posts.fetch_media
  # posts.save

end


if __FILE__ == $0
  main
end



