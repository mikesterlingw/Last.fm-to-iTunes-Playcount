# coding: UTF-8
# This is a tiny utility script to update your iTunes Library's played counts to match your last.fm listening data
#  This is useful if you've had to rebuild your library for any reason.
#  The utility only updates tracks for which the last.fm play count is greater than the iTunes play count.
# Because of how cool the AppleScript hooks are, watch your iTunes libary as this script works!

username = ARGV.pop
logFile = ARGV.pop
options = ARGV

# Redirect errors to log file if filename is provided
if logFile
  $stdout = File.new(logFile, 'w')
end

require 'open-uri'
require 'nokogiri' rescue "This script depends on the Nokogiri gem. Please run '(sudo) gem install nokogiri'."
require 'appscript' rescue "This script depends on the rb-appscript gem. Please run '(sudo) gem install rb-appscript'."
include Appscript

def filter_name(name)
  name.force_encoding("utf-8")
  # This is a hack until I can find out how to do true Unicode normalization in Ruby 1.9
  #  (The Unicode gem doesn't work in 1.9, String#chars.normalize is gone. WTF to do?)
  #  Credit for this goes to my coworker Jordi Bunster
  {
    ['á','à','â','ä','Ä','Â','À','Á','ã','Ã'] => 'a',
    ['é','è','ê','ë','Ë','Ê','È','É']         => 'e',
    ['í','ì','î','ï','Ï','Î','Ì','Í']         => 'i',
    ['ó','ò','ô','ö','Ö','Ô','Ò','Ó','õ','Õ'] => 'o',
    ['ú','ù','û','ü','Ü','Û','Ù','Ú']         => 'u',
    ['ñ','Ñ']                                 => 'n',
    ['ç','Ç']                                 => 'c',
  }.each do |family, replacement|
    family.each { |accent| name.gsub!(accent, replacement) }
  end
  name.downcase.gsub(/^the /, "").gsub(/ the$/, "").gsub(/[^\w]/, "")
end

begin
  charlist = Nokogiri::HTML(open("http://ws.audioscrobbler.com/2.0/user/#{username}/weeklychartlist.xml"))
rescue 
  abort "No user found with username #{username}"
end

filename = "cached_lastfm_data.rbmarshal"
begin
  playcounts = Marshal.load(File.read(filename))

  puts "Reading cached playcount data from disk"
rescue
  puts "No cached playcount data, grabbing fresh data from Last.fm"
  playcounts = {}

  charlist.search('weeklychartlist').search('chart').each do |chartinfo|
    from = chartinfo['from']
    to = chartinfo['to']
    time = Time.at(from.to_i)
    puts "Getting listening data for week of #{time.year}-#{time.month}-#{time.day}"
    sleep 0.1
    begin
      Nokogiri::HTML(open("http://ws.audioscrobbler.com/2.0/user/#{username}/weeklytrackchart.xml?from=#{from}&to=#{to}")).search('weeklytrackchart').search('track').each do |track|
        artist = filter_name(track.search('artist').first.content)
        name = filter_name(track.search('name').first.content)
        playcounts[artist] ||= {}
        playcounts[artist][name] ||= 0
        playcounts[artist][name] += track.search('playcount').first.content.to_i
      end
      rescue
        puts "Error getting listening data for week of #{time.year}-#{time.month}-#{time.day}"
    end
  end

  puts "Saving playcount data"
  File.open(filename, "w+") do |file|
    file.puts(Marshal.dump(playcounts))
  end
end

iTunes = app('iTunes')
iTunes.tracks.get.each do |track|
  begin
    artist = playcounts[filter_name(track.artist.get)]
    if artist.nil?
      puts "Couldn't match up #{track.artist.get}"
      next
    end

    playcount = artist[filter_name(track.name.get)]
    if playcount.nil?
      puts "Couldn't match up #{track.artist.get} - #{track.name.get}"
      next
    end

    if playcount > track.played_count.get
      puts "Setting #{track.artist.get} - #{track.name.get} to playcount of #{playcount} from playcount of #{track.played_count.get}"
      track.played_count.set(playcount)
    else
      puts "Track #{track.artist.get} - #{track.name.get} is chill at playcount of #{playcount}"
    end
  rescue
    puts "Encountered some kind of error on this track"
  end
end