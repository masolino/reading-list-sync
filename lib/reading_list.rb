Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'pry'
require 'awesome_print'
require 'yaml'

begin
  CONFIG = YAML.load_file('config/secrets.yml')
#rescue
#  raise "Error reading config file config/secrets.yml. Please check the README for instructions"
end

require 'nokogiri'
require 'pinboard'
require 'open3'
require 'typhoeus'
require 'json'

require 'bookmark'
require 'safari_bookmark'
require 'pinboard_bookmark'

module ReadingList
  def self.sync!
    counts = {total: 0, skipped: 0, replaced: 0, added: 0, removed: 0}
    SafariBookmark.reading_list.each do |bookmark|
      counts[:total] += 1
      p = PinboardBookmark.new(bookmark)
      puts "---"
      puts "title:   #{p.title}"
      puts "  url:   #{p.url}"
      puts " date:   #{p.date_added}"
      puts "  age:   #{p.post_age} days ago"
      puts " pinboard status/update:"
      if p.exists?
        if bookmark.still_online?
          puts "   => exists, current tags: #{p.tags}"
          if p.remote.tag.empty?
            p.tags = p.smart_tags
            puts "      ... suggested: #{p.tags}"
            # remove and re-add if there are some tags
            if p.tags.any?
              p.delete!
              p.save!
              # ap p
              puts "      ... replaced!"
              counts[:replaced] += 1
            else
              puts "      ... (skipped, no tags to add)"
              counts[:skipped] += 1
            end
          else
            puts "      ... (skipped, has tags)"
            counts[:skipped] += 1
          end
        else
          puts "   !> exists, but url no longer loads. removing!"
          p.delete!
          counts[:removed] += 1
        end
      else
        # move reading list to pinboard
        p.tags = p.smart_tags
        p.save!
        puts "  * adding with tags #{p.smart_tags}"
        counts[:added] += 1

        self.add_to_evernote p.url, p.title, p.smart_tags
      end
    end
    puts "\nStats:\n"
    ap counts
    puts
  end

  def self.osascript(script)
    system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
  end

  def self.add_to_evernote(url, title, tags)

    webarchive_filename = "#{self.parameterize title}.webarchive"

    webarchive = "~/Desktop/#{webarchive_filename}"

    self.save_webarchive_on_desktop(url, webarchive)

    self.osascript <<-END
      tell application "Evernote"
        if (not (notebook named "Bookmarks" exists)) then
          make notebook with properties {name:"Bookmarks"}
        end if
        set note_url to "#{url}"
        set new_note to create note title "#{title}" from url "#{url}" notebook "Bookmarks"
        set the source URL of new_note to note_url
        repeat with theTag in {#{self.clean_tags tags}}
          if (not (tag named theTag exists)) then
            make tag with properties {name:theTag}
          end if
          assign tag theTag to new_note
        end repeat

        set textPathDesktopFolder to (path to desktop folder from user domain) as text
        set file_webarchive to (textPathDesktopFolder & "#{webarchive_filename}")

        append new_note attachment file file_webarchive

      end tell
    END

    self.delete_webarchive_from_desktop(webarchive)
  end

  def self.save_webarchive_on_desktop(url, file)
    system "webarchiver -url #{url} -output #{file}"
  end

  def self.delete_webarchive_from_desktop(file)
    system "rm -rf #{file}"
  end

  def self.clean_tags(tags)
    tags.to_json.tr('[', '').tr(']', '')
  end

  def self.parameterize(string, sep = '-')
    # replace accented chars with their ascii equivalents
    parameterized_string = string
    # Turn unwanted chars into the separator
    parameterized_string.gsub!(/[^a-z0-9\-_]+/, sep)
    unless sep.nil? || sep.empty?
      re_sep = Regexp.escape(sep)
      # No more than one of the separator in a row.
      parameterized_string.gsub!(/#{re_sep}{2,}/, sep)
      # Remove leading/trailing separator.
      parameterized_string.gsub!(/^#{re_sep}|#{re_sep}$/, '')
    end
    parameterized_string.downcase
  end
end
