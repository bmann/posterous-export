#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'net/http'
require 'date'
require 'nokogiri'


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
  response = call_api(SITE, site, PUBLIC_POSTS)
  if [200,201].include? response.code.to_i
    pages = Array.new

    response.header["x-total-pages"].to_i.times {|page|
      #Posterous API uses index starting at one
      pages[page] = call_api(SITE, site, PUBLIC_POSTS, "?page=#{page + 1}").body
    }
    return pages
  else
    #FIXME: we can show a better information to the user
      return nil
  end

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
    @date = DateTime.parse(data["display_date"])
    # TODO: test with a post with comments
    @comments = data["comments"]
    @tags = if data["tags"].nil? then [] else data["tags"].map {|tag| tag["name"] } end
    @images = data["media"]["images"].map {|item| item.values.map{|value| value["url"] } }.flatten || Array.new
    @audio_files = data["media"]["audio_files"].map{|value| value["url"] }
    @videos = data["media"]["videos"].map{|value| value["url"] }
  end

  def save_media(path, uri)
    response = fetch(uri)

    raise LoadRessourceError unless [200,201].include? response.code.to_i

    FileUtils.mkdir_p path unless File.exists? path
    File.open("#{path}/#{uri.split("/")[-2..-1].join("_")}", "wb") { |f| f << response.body }
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
    #TODO: convert audio and video links
    @body = @body.gsub(%r(<a href="http://[^.]*.(posterous.com/getfile/files.posterous.com/([^.]*\.))([^"]*)"(.*)src="http://.*\1([^"]*)")) {|md| #" this is a little workaround for the Ruby mode of Emacs
      #FIXME: this is a workaround for ruby 1.8.7 (2011-12-28 patchlevel 357) [x86_64-linux]
      #the String#split breaks the global variables
      three = $3
      four = $4
      five = $5
      new_name = $2.split("/")[-2..-1].join("_")
      data = <<-EOS
<a href="./images/#{new_name}#{three}"#{four}src="./images/#{new_name}#{five}"
EOS
    }
    html_doc = Nokogiri::HTML(@body)

    videos = html_doc.css("div.p_video_embed")
    videos.map {|video|
      #TODO: change the divs content

    }
    audios = html_doc.css("div.p_audio_embed")
    audios.map {|audio|
      #TODO: change the divs content

    }
  end

  def save
    data = <<-EOS
---
layout: post
title: #{@title}
date: #{@date.strftime("%F %H:%M")}
categories:#{@tags.reduce("") {|acc, tag| acc += "\n- #{tag}"}}
---

#{@body}
EOS

    File.open("#{@date.strftime("%F")}-#{@slug}.markdown", "w") {|file|
      file << data
    }
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
    pages = public_posts("markdownexport")
    pages = pages.map {|page|
      ruby_data = JSON.parse(page)
      ruby_data.map {|entry| Post.new(entry) }
    }
  end

  pages.each{|page|
    page.each{|post| 
      post.convert
      post.fetch_media
      post.save
    }
  }
end


if __FILE__ == $0
  main
end



