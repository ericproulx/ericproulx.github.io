---
layout: post
title:  "GET/HEAD = readonly? 🤔"
---

By [definition](https://restfulapi.net/http-methods/#get), GET/HEAD endpoints should read stuff only. In other words, no writing at all, but how can you make sure it's the case when you work in a large application? The question needs to be asked
if you're about to use read-only replicas and activate the [automatic role switching feature](https://guides.rubyonrails.org/active_record_multiple_databases.html#activating-automatic-role-switching)

# Let's talk about strategies.

Depending of your current situation (multiple teams , multiple endpoints 😅, etc...), you need a scalable and sustainable solution over time.
I'm talking about some kind of tool that will give some awareness first and gives hard stops (exceptions) through progression.
Being smooth at the beginning and tighten things up at some point.

Leveraging `config.active_support.deprecation` feels like the best choice to me since you can easily change the behavior through environments.
Warnings is also a good choice depending if you're handling them or not. I found a [great article](https://www.bugsnag.com/blog/managing-warnings-in-ruby) about that. 

## Instrumentation is your friend

A while ago, I came up with a neat solution using [instrumentation](https://guides.rubyonrails.org/active_support_instrumentation.html) and a [middleware](https://guides.rubyonrails.org/rails_on_rack.html).
Basically, it wraps all non GET/HEAD request with a subscription to [sql.active_record](https://guides.rubyonrails.org/active_support_instrumentation.html#active-record).
The subscription's callback looks at the payload for writable sql statements. It will then apply the chosen strategy depending of your choice if any writable statements were found.

This middleware does not log SQL statements but a `debug` parameter could be added to show a complete list (might be useful)
Lastly, 
```ruby
# frozen_string_literal: true
# lib/middlewares/read_only_middleware.rb

module Middlewares
  class ReadOnlyMiddleware
    WRITABLE_SQL_STATEMENTS = %w[INSERT UPDATE DELETE UPSERT MERGE].freeze

    thread_mattr_accessor :found_sql_writable_statement

    attr_reader :app, :reporting_strategy

    def initialize(app, strategy: nil)
      @app = app
      @reporting_strategy = resolve_strategy(strategy)
    end

    def call(env)
      request = Rack::Request.new(env)
      return _call(env) unless request.get? || request.head?

      self.found_sql_writable_statement = false
      response = nil
      ActiveSupport::Notifications.subscribed(method(:notification_callback), 'sql.active_record') do
        response = _call(env)
      end
      report(request)
      response
    end

    private

    def _call(env)
      @app.call(env)
    end

    private

    def notification_callback(*args)
      event = ActiveSupport::Notifications::Event.new(*args)
      return if found_sql_writable_statement || !event.payload[:sql].start_with?(*WRITABLE_SQL_STATEMENTS)

      self.found_sql_writable_statement = true
    end

    def report(request)
      return unless found_sql_writable_statement

      reporting_strategy.warn("The following endpoint is not readonly: #{endpoint_info(request)}")
    end

    def endpoint_info(request)
      path_params = request.env[ActionDispatch::Http::Parameters::PARAMETERS_KEY]
      "#{path_params[:controller]}##{path_params[:action]}"
    end

    def resolve_strategy(strategy)
      case strategy
      when :deprecation
        ActiveSupport::Deprecation
      else
        Rails.logger
      end
    end
  end
end

```
In your `application.rb`
```ruby
require 'middlewares/read_only_middleware'
config.middleware.use Middlewares::ReadOnlyMiddleware, strategy: :deprecation
```

`ActiveSupport::Deprecation` and `Rails.logger` came naturally to my mind since you might already have a strategy(:notify, :raise, etc...) in your app based on your environment.










