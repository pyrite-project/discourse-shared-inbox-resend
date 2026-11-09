# frozen_string_literal: true

require "mail"
require "nokogiri"
require "digest"

module SharedInbox
  class Email
    class Invalid < StandardError; end

    attr_reader :data, :headers

    def initialize(data)
      @data = data
      @headers = data.fetch("headers", {}).to_h.transform_keys { |key| key.to_s.downcase }
      raise Invalid, "missing_sender" unless sender
      raise Invalid, "missing_message_id" unless message_id
    end

    def self.address(value)
      return if value.to_s.match?(/[\r\n]/)
      addresses = Mail::AddressList.new(value.to_s).addresses
      return unless addresses.size == 1
      address = addresses.first.address.to_s.downcase
      address if address.match?(/\A[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+\z/) && address.length <= 254
    rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
      nil
    end

    def self.ids(value)
      value.to_s.scan(/<[^<>\s]{1,900}>/).last(50)
    end

    def sender
      @sender ||= self.class.address(data["from"])
    end

    def reply_to
      values = Array(data["reply_to"]).presence || [headers["reply-to"]]
      self.class.address(values.first) || sender
    end

    def recipients
      (Array(data["to"]) + Array(data["cc"]) + Array(data["bcc"]) + Array(data["received_for"]))
        .filter_map { |value| self.class.address(value) }.uniq
    end

    def message_id
      self.class.ids(data["message_id"] || headers["message-id"]).first
    end

    def references
      (self.class.ids(headers["references"]) + self.class.ids(headers["in-reply-to"])).uniq.reverse
    end

    def unsubscribe?
      headers.key?("list-unsubscribe") || headers.key?("unsubscribe")
    end

    def automated?
      auto = headers["auto-submitted"].to_s.downcase
      (auto.present? && auto != "no") || headers["x-shared-inbox"].to_s == "1"
    end

    def subject
      data["subject"].to_s.gsub(/[\r\n\x00-\x1f]/, " ").strip.first(900).presence || I18n.t("shared_inbox.no_subject")
    end

    def text
      return data["text"].to_s if data["text"].present?
      self.class.html_to_text(data["html"])
    end

    def self.html_to_text(html)
      fragment = Nokogiri::HTML.fragment(html.to_s)
      fragment.css("script,style,head").remove
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css("p,div,li,tr,h1,h2,h3,blockquote").each { |node| node.add_next_sibling("\n") }
      fragment.text.strip
    end

    # A code block keeps untrusted email text from creating mentions, oneboxes,
    # images or forged Discourse Markdown. Never insert email HTML into cooked.
    def raw
      body = "#{I18n.t('shared_inbox.from')}: #{sender}\n\n#{text.gsub("\u0000", "")}"
      attachments = Array(data["attachments"]).map { |item| item["filename"].to_s.gsub(/[\r\n]/, " ") }
      body += "\n\n#{I18n.t('shared_inbox.attachments')}: #{attachments.join(', ')}" if attachments.present?
      limit = [SiteSetting.max_post_length.to_i - 1000, 1000].max
      body = body.truncate(limit)
      fence = "`" * [3, body.scan(/`+/).map(&:length).max.to_i + 1].max
      if body.length + 2 * fence.length + 8 > SiteSetting.max_post_length.to_i
        body = body.truncate([SiteSetting.max_post_length.to_i / 3 - 20, 20].max)
        fence = "`" * [3, body.scan(/`+/).map(&:length).max.to_i + 1].max
      end
      "#{fence}text\n#{body}\n#{fence}"
    end
  end
end
