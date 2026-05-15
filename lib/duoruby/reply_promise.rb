# frozen_string_literal: true

require "async"
require "async/promise"
require "duoruby/reply_error"

module DuoRuby
  # Async-backed server-side reply promise.
  #
  # It keeps Async::Promise's native #wait API and adds the small PromiseV2-like
  # surface DuoRuby exposes across runtimes.
  class ReplyPromise < Async::Promise
    def await(...)
      wait(...)
    end

    alias_method :__await__, :await

    def then(&handler)
      return self unless handler

      if resolved?
        handler.call(wait) if completed?
      else
        schedule { call_success(handler) }
      end

      self
    end

    def fail(&handler)
      return self unless handler

      if resolved?
        call_failure(handler)
      else
        schedule { call_failure(handler) }
      end

      self
    end

    alias_method :rescue, :fail

    private

    def call_failure(handler)
      wait
    rescue StandardError => error
      handler.call(error)
    end

    def call_success(handler)
      handler.call(wait)
    rescue StandardError
      nil
    end

    def schedule(&block)
      if (task = Async::Task.current?)
        task.async(&block)
      else
        Thread.new(&block)
      end
    end
  end
end
