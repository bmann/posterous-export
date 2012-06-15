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

def call_api(*args)
  fetch(POSTEROUS_URL + args.join)
end

def public_posts(site)
  call_api(SITE, site, PUBLIC_POSTS)
end

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


def main

  begin
    # try to authenticate using posterous gem
    @user = User.me
    pp @user

    pp "Posts: #{@user.posts}"

    @site = Site.find("the3six5")

    pp @site

    pp "Posts from the3six5: #{@site.posts}"
  rescue Posterous::Connection::ConnectionError
    # fail back to unauthenticated access
    res = public_posts("the3six5")
    pp res.body
  end

end



main
