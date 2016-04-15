# encoding: utf-8
require 'integration_test_helper'
require 'slack'

class SlackTest < ActiveSupport::TestCase

  # needed to check correct behavior
  slack_group = Group.create_if_not_exists(
    name: 'Slack',
    updated_by_id: 1,
    created_by_id: 1
  )

  # check
  test 'base' do

    if !ENV['SLACK_CI_CHANNEL']
      raise "ERROR: Need SLACK_CI_CHANNEL - hint SLACK_CI_CHANNEL='ci-zammad'"
    end
    if !ENV['SLACK_CI_WEBHOOK']
      raise "ERROR: Need SLACK_CI_WEBHOOK - hint SLACK_CI_WEBHOOK='https://hooks.slack.com/services/...'"
    end
    if !ENV['SLACK_CI_CHECKER_TOKEN']
      raise "ERROR: Need SLACK_CI_CHECKER_TOKEN - hint SLACK_CI_CHECKER_TOKEN='...'"
    end

    channel = ENV['SLACK_CI_CHANNEL']
    webhook = ENV['SLACK_CI_WEBHOOK']

    # set system mode to done / to activate
    Setting.set('system_init_done', true)
    Setting.set('slack_integration', true)

    items = [
      {
        group_ids: [slack_group.id],
        types: %w(create update),
        webhook: webhook,
        channel: channel,
        username: 'zammad bot',
        expand: false,
      }
    ]
    Setting.set('slack_config', { items: items })

    # case 1
    customer = User.find(2)
    hash     = hash_gen
    text     = "#{rand_word}... #{hash}"

    default_group = Group.first
    ticket1 = Ticket.create(
      title:         text,
      customer_id:   customer.id,
      group_id:      default_group.id,
      state:         Ticket::State.find_by(name: 'new'),
      priority:      Ticket::Priority.find_by(name: '2 normal'),
      updated_by_id: 1,
      created_by_id: 1,
    )
    article1 = Ticket::Article.create(
      ticket_id:     ticket1.id,
      body:          text,
      type:          Ticket::Article::Type.find_by(name: 'note'),
      sender:        Ticket::Article::Sender.find_by(name: 'Customer'),
      internal:      false,
      updated_by_id: 1,
      created_by_id: 1,
    )

    Observer::Transaction.commit
    Delayed::Worker.new.work_off

    # check if message exists
    assert_not(slack_check(channel, hash))

    ticket1.state = Ticket::State.find_by(name: 'open')
    ticket1.save

    Observer::Transaction.commit
    Delayed::Worker.new.work_off

    # check if message exists
    assert_not(slack_check(channel, hash))

    # case 2
    hash = hash_gen
    text = "#{rand_word}... #{hash}"

    ticket2 = Ticket.create(
      title:         text,
      customer_id:   customer.id,
      group_id:      slack_group.id,
      state:         Ticket::State.find_by(name: 'new'),
      priority:      Ticket::Priority.find_by(name: '2 normal'),
      updated_by_id: 1,
      created_by_id: 1,
    )
    article2 = Ticket::Article.create(
      ticket_id:     ticket2.id,
      body:          text,
      type:          Ticket::Article::Type.find_by(name: 'note'),
      sender:        Ticket::Article::Sender.find_by(name: 'Customer'),
      internal:      false,
      updated_by_id: 1,
      created_by_id: 1,
    )

    Observer::Transaction.commit
    Delayed::Worker.new.work_off

    # check if message exists
    assert(slack_check(channel, hash))

    hash = hash_gen
    text = "#{rand_word}... #{hash}"

    ticket2.title = text
    ticket2.save

    Observer::Transaction.commit
    Delayed::Worker.new.work_off

    # check if message exists
    assert(slack_check(channel, hash))

  end

  def hash_gen
    (0...10).map { ('a'..'z').to_a[rand(26)] }.join
  end

  def rand_word
    words = [
      'dog',
      'cat',
      'house',
      'home',
      'yesterday',
      'tomorrow',
      'new york',
      'berlin',
      'coffee script',
      'java script',
      'bob smith',
      'be open',
      'really nice',
      'stay tuned',
      'be a good boy',
      'invent new things',
    ]
    words[rand(words.length)]
  end

  def slack_check(channel_name, search_for)

    Slack.configure do |config|
      config.token = ENV['SLACK_CI_CHECKER_TOKEN']
    end

    Slack.auth_test

    client = Slack::Client.new
    channels = client.channels_list['channels']
    channel_id = nil
    channels.each {|channel|
      next if channel['name'] != channel_name
      channel_id = channel['id']
    }
    if !channel_id
      raise "ERROR: No such channel '#{channel_name}'"
    end

    channel_history = client.channels_history(channel: channel_id)
    if !channel_history
      raise "ERROR: No history for channel #{channel_name}/#{channel_id}"
    end
    if !channel_history['messages']
      raise "ERROR: No history messages for channel #{channel_name}/#{channel_id}"
    end
    channel_history['messages'].each {|message|
      next if !message['text']
      if message['text'] =~ /#{search_for}/i
        p "SUCCESS: message with #{search_for} found!"
        return true
      end
    }
    #raise "ERROR: No such message containing #{search_for} in history of channel #{channel_name}/#{channel_id}"
    false
  end

end