#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'net/http'
require 'date'

# Reverse markdown includes
require 'rexml/document'
require 'benchmark'
include REXML
include Benchmark


require 'posterous'
Posterous.config = {
  'username'  => '',
  'password'  => ''
}


# ---------------
# Edit below to configure
# ---------------

SITE = "markdownexport"		# SHORTNAMEOFYOURSITE.posterous.com
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
     if uri.nil?
         STDERR.puts "save_media: Variable uri is nil"
     else
         STDERR.puts "save_media: Variable uri is #{uri.inspect}"
         response = fetch(uri)
 
         raise LoadRessourceError unless [200,201].include? response.code.to_i
 
         FileUtils.mkdir_p path unless File.exists? path
         File.open("#{path}/#{uri.split("/")[-2..-1].join("_")}", "wb") { |f| f << response.body }
     end
  end

  def fetch_images
    STDERR.puts "fetching images"
    @images.each{|image| save_media(IMAGE_PATH, image) }
  end

  def fetch_audio
    STDERR.puts "fetching audio"
    # NOTE: using only the images folder
    @audio_files.each{|audio| save_media(IMAGE_PATH, audio) }
  end

  def fetch_videos
    STDERR.puts "fetching video"
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

    # Transform body into 
    @body = ReverseMarkdown.new.parse_string(@body)

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
      post.fetch_media
      post.save
    }
  }
end



=begin
This is the reverse markdown script, which can be found here:
https://github.com/xijo/reverse_markdown

The file is attached here instead of required or loadedd because of the single file requirement.
=end

# reverse markdown for ruby
# author: JO
# e-mail: xijo@gmx.de
# date: 14.7.2009
# version: 0.1
# license: GPL
# taken from https://github.com/xijo/reverse-markdown/raw/master/reverse_markdown.rb

# TODO
# - ol numbering is buggy, in fact doesn't matter for markdown code
# -

class ReverseMarkdown

  # set basic variables:
  # - @li_counter: numbering list item (li) tags in an ordered list (ol)
  # - @links:      hold the links for adding them to the bottom of the @output
  #                this means 'reference style', please take a look at http://daringfireball.net/projects/markdown/syntax#link
  # - @outout:     fancy markdown code in here!
  # - @indent:     control indention level for nested lists
  # - @errors:     appearing errors, like unknown tags, go into this array
  def initialize()
    @li_counter = 0
    @links = []
    @output = ""
    @indent = 0
    @errors = []
  end

  # Invokes the HTML parsing by using a string. Returns the markdown code in @output.
  # To garantuee well-formed xml for REXML a <root> element will be added, but has no effect.
  # After parsing all elements, the 'reference style'-links will be inserted.
  def parse_string(string)
    doc = Document.new("<root>\n"+string+"\n</root>")
    parse_element(doc.root, :none)
    insert_links()
    @output
  end

  # Parsing an element and its children (recursive) and writing its markdown code to @output
  # 1. do indent for nested list items
  # 2. add the markdown opening tag for this element
  # 3a. if element only contains text, handle it like a text node
  # 3b. if element is a container handle its children, which may be text- or element nodes
  # 4. finally add the markdown ending tag for this element
  def parse_element(element, parent)
    name = element.name.to_sym
    # 1.
    @output << indent() if name.eql?(:li)
    # 2.
    @output << opening(element, parent)

    # 3a.
    if (element.has_text? and element.children.size < 2)
      @output << text_node(element, parent)
    end

    # 3b.
    if element.has_elements?
      element.children.each do |child|
        # increase indent if nested list
        @indent += 1 if element.name=~/(ul|ol)/ and parent.eql?(:li)

        if child.node_type.eql?(:element)
          parse_element(child, element.name.to_sym)
        else
          if parent.eql?(:blockquote)
            @output << child.to_s.gsub("\n ", "\n>")
          else
            @output << child.to_s
          end
        end

        # decrease indent if end of nested list
        @indent -= 1 if element.name=~/(ul|ol)/ and parent.eql?(:li)
      end
    end

    # 4.
    @output << ending(element, parent)
  end

  # Returns opening markdown tag for the element. Its parent matters sometimes!
  def opening(type, parent)
    case type.name.to_sym
      when :h1
        "# "
      when :li
        parent.eql?(:ul) ? " - " : " "+(@li_counter+=1).to_s+". "
      when :ol
        @li_counter = 0
        ""
      when :ul
        ""
      when :h2
        "## "
      when :h3
        "### "
      when :h4
        "#### "
      when :h5
        "##### "
      when :h6
        "###### "
      when :em
        "*"
      when :strong
        "**"
      when :blockquote
        # remove leading newline
        type.children.first.value = ""
        "> "
      when :code
        parent.eql?(:pre) ? "    " : "`"
      when :a
        "["
      when :img
        "!["
      when :hr
        "----------\n\n"
      when :root
        ""
      else
        @errors << "unknown start tag: "+type.name.to_s
        ""
    end
  end

  # Returns the closing markdown tag, like opening()
  def ending(type, parent)
    case type.name.to_sym
      when :h1
        " #\n\n"
      when :h2
        " ##\n\n"
      when :h3
        " ###\n\n"
      when :h4
        " ####\n\n"
      when :h5
        " #####\n\n"
      when :h6
        " ######\n\n"
      when :p
        parent.eql?(:root) ? "\n\n" : "\n"
      when :ol
        parent.eql?(:li) ? "" : "\n"
      when :ul
        parent.eql?(:li) ? "" : "\n"
      when :em
        "*"
      when :strong
        "**"
      when :li
        ""
      when :blockquote
        ""
      when :code
        parent.eql?(:pre) ? "" : "`"
      when :a
        @links << type.attribute('href').to_s
        "][" + @links.size.to_s + "] "
      when :img
        @links << type.attribute('src').to_s
        "" + type.attribute('alt').to_s + "][" + @links.size.to_s + "] "
        "#{type.attribute('alt')}][#{@links.size}] "
      when :root
        ""
      else
        @errors << "  unknown end tag: "+type.name.to_s
        ""
    end
  end

  # Perform indent: two space, @indent times - quite simple! :)
  def indent
    str = ""
    @indent.times do
      str << "  "
    end
    str
  end

  # Return the content of element, which should be just text.
  # If its a code block to indent of 4 spaces.
  # For block quotation add a leading '>'
  def text_node(element, parent)
    if element.name.to_sym.eql?(:code) and parent.eql?(:pre)
      element.text.gsub("\n","\n    ") << "\n"
    elsif parent.eql?(:blockquote)
      element.text.gsub!("\n ","\n>")
      return element.text
    else
      element.text
    end
  end

  # Insert the mentioned reference style links.
  def insert_links
    @output << "\n"
    @links.each_index do |index|
      @output << "  [#{index+1}]: #{@links[index]}\n"
    end
  end

  # Print out all errors, that occured and have been written to @errors.
  def print_errors
    @errors.each do |error|
      puts error
    end
  end

  # Perform a benchmark on a given string n-times.
  def speed_benchmark(string, n)
    initialize()
    bm(15) do |test|
      test.report("reverse markdown:")    { n.times do; parse_string(string); initialize(); end; }
    end
  end

end
# End of the reverse markdown script

if __FILE__ == $0
  main
end

