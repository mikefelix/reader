require 'rss'
require 'open-uri'

class ProcessFeed
  include Sidekiq::Worker
  sidekiq_options :queue => :process

  def perform(id, file_path, repeat)
    body = File.open(file_path, "r").read
    body = body.encode('UTF-8', :invalid => :replace, :replace => '')
    body = body.encode('UTF-16', :invalid => :replace, :replace => '')
    body = body.encode('UTF-8', :invalid => :replace, :replace => '')

    body = Nokogiri::XML.parse(body).to_s
    parsed_feed = Feedzirra::Feed.parse(body) do |t|
      # apparently, this block is an error handling block
      #feed = Feed.find feed_id
      #feed.parse_errors ||= 0
      #feed.parse_errors = feed.parse_errors + 1
      #feed.fetchable = false if feed.parse_errors > 10
      #feed.save
      ap t
      ap "THIS BROKE"
      return
    end

    entries = parsed_feed.entries.select do |entry|
      EntryGuid.where(feed_id: id, guid: ProcessFeed.entry_guid(entry)).count == 0
    end

    entries.each do |entry|
      ProcessFeed.process_entry(id, entry)
    end

    File.delete file_path
    PollFeed.requeue_polling(id)

    feed = Feed.where(id: id).first
    feed.subscriptions.each { |sub| UpdateSubscriptionCount.perform_async(sub.id) }

  rescue

    feed.increment!(:parse_errors) if feed
    em =  "ERROR: #{$!}: #{id} - #{feed.try(:feed_url)}"
    ap em
  end


  def self.process_entries(feed_id, entries)
    entries.each do |entry|
      process_entry(feed_id, entry)
    end
  end

  def self.entry_guid(entry)
    guid = entry.respond_to?(:guid) ? entry.guid : nil
    guid ||= entry.respond_to?(:entry_id) ? entry.entry_id : nil
    guid ||= entry.url
    guid ||= entry.title
  end

  def self.process_entry(feed_id, entry)
    content = entry.respond_to?(:content) ? entry.content : nil
    content ||= entry.summary

    guid = entry_guid(entry)

    url = entry.url || guid
    if url && guid
      entry_model = Entry.find_or_initialize_by_feed_id_and_guid(feed_id, guid)

      entry_date = entry.published
      entry_date ||= (entry.respond_to?(:updated)) ? entry.updated : nil
      entry_date ||= Time.current.to_formatted_s(:db) + " UTC"

      if entry_model.new_record?
        entry_model.attributes= {:feed_id => feed_id,
                                 :title => entry.title,
                                 :author => entry.author,
                                 :content => content,
                                 :url => url,
                                 :guid => guid,
                                 :published_at => entry_date}

        entry_model.save!
        Rails.logger.info "Added entry to #{feed_id}: #{entry.title}"
      else
        entry_model.update_attributes!(:feed_id => feed_id,
                                       :title => entry.title,
                                       :author => entry.author,
                                       :content => content,
                                       :url => url,
                                       :guid => guid,
                                       :published_at => entry_date)
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    ap "feed: #{feed_id} - guid: #{guid} - #{e} - #{e.message}"
  end
end
