# Copyright 2011 Tobias Crawley
#
# This file is part of github-rss.
#
# github-rss is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# github-rss is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with github-rss.  If not, see <http://www.gnu.org/licenses/>.
  
require 'cgi'
require 'open-uri'
require 'json'
require 'nokogiri'
require 'restclient'

class FeedParser
  def initialize(feed_url)
    @feed_url = feed_url.gsub(/^http:/, 'https:')
    if @feed_url =~ %r{token=(.*)$}
      @token = $1
    end
  end

  def parse
    begin
      @feed = Nokogiri::XML(open(@feed_url))
    rescue Exception => ex
      puts "Failed to parse #{@feed_url}: #{ex}"
      raise ParseException.new("Failed to parse #{@feed_url}", ex)
    end
    add_diffs
    @feed.to_xml
  end

  def add_diffs
    @feed.css("feed entry").each do |entry|
      commit_url = entry.css("link").first['href']
      if commit_url =~ %r{github.com/(.*?)/(.*?)/commit/([a-f0-9]*)$}
        user, repo, sha = $1, $2, $3
        key = "#{user}/#{repo}/commits/#{sha}"
        puts "Checking cache for #{key}"
        commit = CACHE.get(key)
        if !commit
          puts "#{key} not in cache"
          args = ["https://api.github.com/repos/#{key}"]
          args += ["access_token", @token] if @token
          commit = RestClient::Resource.new(*args).get
          CACHE.set(key, commit)
        end
       
        commit = JSON.parse(commit)
        author = "\n"
        author << "<b><pre>" << commit["author"]["name"] << "</pre></b>\n\n"
        entry.css('content').first.content += author
        diff = "<pre>"
        (commit["files"] || []).each do |f|
          f_diff = f['patch']
          if f_diff
            diff << "\n\n\n===> " << f['filename'] << "\n\n"
            diff << "#{escape(f_diff)}" 
          end
        end
        diff << "</pre>"
        entry.css('content').first.content += diff
      end

    end
  end
  
  def escape(str)
    str ? CGI.escapeHTML(str) : ""
  end
end


class ParseException < RuntimeError
  attr_reader :exception
  
  def initialize(msg, cause)
    super("#{msg}: #{cause}")
    @exception = cause
  end
end
