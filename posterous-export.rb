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


# ---------------
# Edit below to configure
# ---------------

SITE = "nancibonfim"		# SHORTNAMEOFYOURSITE.posterous.com
EXPORT_PATH = "_posts"		# /path/to/export/folder -- local directory "_posts" by default
IMAGE_PATH = "images"		# /path/to/images/folder -- local directory "images" by default
IMAGE_REL_PATH = "/images"	# absolute path from webroot to images folder which is how images & other media will be linked to
EXTENSION = "markdown"		# file extension for posts - defaults to .markdown, could also be .md

#
# ---------------
#

include Posterous

POSTEROUS_URL = "http://posterous.com/api/2/"
SITE_PATH = "sites/"
PUBLIC_POSTS = "/posts/public"

#debug
require 'pp'

# little wrapper to the fecth method
def call_api(*args)
  fetch(POSTEROUS_URL + args.join)
end

# little API wrapper
def public_posts(site)
  response = call_api(SITE_PATH, site, PUBLIC_POSTS)
  if [200,201].include? response.code.to_i
    pages = Array.new

    response.header["x-total-pages"].to_i.times {|page|
      #Posterous API uses index starting at one
      pages[page] = call_api(SITE_PATH, site, PUBLIC_POSTS, "?page=#{page + 1}").body
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
    @images.each{|image| save_media(IMAGE_PATH, image) }
  end

  def fetch_audio
    # NOTE: using only the images folder
    @audio_files.each{|audio| save_media(IMAGE_PATH, audio) }
  end

  def fetch_videos
    # NOTE: using only the images folder
    @videos.each{|video| save_media(IMAGE_PATH, video) }
  end

  def convert_list(list_doc, depth, kind)
    list_doc.children.each {|item|
      item.remove if !item.element? && item.content == "\n"
    }

    list_doc.children.select{|child| child.name == "li"}.each_with_index {|li, index|
      li.children[0].content = "#{" " * 4 * depth}#{kind == :ol ? ((index + 1).to_s + '.') : '*'} #{li.children[0].content.chomp}\n"
      if li.children.size > 1
        convert_list(li.children[1], depth + 1, li.children[1].name.to_sym)
      end

      li.replace("#{li.inner_html.chomp}")
    }

    list_doc.replace("#{list_doc.inner_html.chomp}")
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
<a href="#{IMAGE_REL_PATH}/#{new_name}#{three}"#{four}src="#{IMAGE_REL_PATH}/#{new_name}#{five}"
EOS
    }
    html_doc = Nokogiri::HTML(@body)

    # encloses an HTML p tag within newlines
    html_doc.css("p").each {|par| par.replace("\n#{par.inner_html}\n")}

    # convert the headers
    (1..6).each {|i|
      html_doc.css("h#{i}").each {|header| header.replace("#{'#' * i} #{header.inner_html}") }
    }

    # convert unordered lists
    html_doc.css("body > ul").each {|ul|
      convert_list(ul, 0, :ul)
    }

    #convert ordered lists
    html_doc.css("body > ol").each {|ol|
      convert_list(ol, 0, :ol)
    }

    #TODO: text formatting

    #TODO: links

    #TODO: blockquote, pre

    videos = html_doc.css("div.p_video_embed")
    videos.map {|video|
      #TODO: change the divs content

    }
    audios = html_doc.css("div.p_audio_embed")
    audios.map {|audio|
      #TODO: change the divs content

    }

    @body = html_doc.css("body").inner_html

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

    FileUtils.mkdir_p EXPORT_PATH unless File.exists? EXPORT_PATH
    File.open("#{EXPORT_PATH}/#{@date.strftime("%F")}-#{@slug}.#{EXTENSION}", "w") {|file|
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

    @site = Site.find(SITE)

    pp @site

    pp "Posts from #{SITE} #{@site.posts}"
  rescue Posterous::Connection::ConnectionError
    # fail back to unauthenticated access
    pages = public_posts(SITE)
    pages = pages.map {|page|
      ruby_data = JSON.parse(page)
      ruby_data.map {|entry| Post.new(entry) }
    }
  end

  pages.each{|page|
    page.each{|post| 
      post.convert
#XXX      post.fetch_media
      post.save
    }
  }
end


if __FILE__ == $0
  main
end



