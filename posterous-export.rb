#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'net/http'

require 'posterous'
Posterous.config = {
  'username'  => '',
  'password'  => ''
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


# Error class for not implemented methods
class NotImplementedException < StandardError
end

class TooManyRedirectsError < StandardError
end

class LoadRessourceError < StandardError
end

# fetch method based on the Net::HTTP documentation
def fetch(uri_str, limit = 10)
  raise TooManyRedirectsError, 'too many HTTP redirects' if limit == 0

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

  def save_media(path, uri)
    response = fetch(uri)

    raise LoadRessourceError unless [200,201].include? response.code.to_i

    FileUtils.mkdir_p path unless File.exists? path
    File.open("#{path}/#{uri.split("/")[-2..-1].join}", "wb") { |f| f << response.body }
  end

  def fetch_images
    @images.each{|image| save_media("images", image) }
  end

  def fetch_audio
    @audio_files.each{|audio| save_media("audio_files", audio) }
  end

  def fetch_videos
    @videos.each{|video| save_media("videos", video) }
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

  posts.each{| post| 
#    post.convert
    post.fetch_media
#    post.save
  }

end


if __FILE__ == $0
  main
end



