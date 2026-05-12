# frozen_string_literal: true

require "duoruby/frontend"
require "glimmer-dsl-web"

module Counter
  class CounterModel
    attr_accessor :value

    def initialize
      @value = 0
    end
  end

  class CounterPage
    include Glimmer::Web::Component

    option :model
    option :frontend

    markup {
      div(style: "font-family: sans-serif; max-width: 320px; margin: 60px auto; text-align: center;") {
        h1("Counter")

        p(style: "font-size: 3em; margin: 20px 0;") {
          inner_text <= [model, :value]
        }

        div {
          button(style: "margin: 4px; padding: 8px 20px;") {
            inner_text "−"
            onclick { frontend.send(:decrement) }
          }

          button(style: "margin: 4px; padding: 8px 20px;") {
            inner_text "Reset"
            onclick { frontend.send(:reset) }
          }

          button(style: "margin: 4px; padding: 8px 20px;") {
            inner_text "+"
            onclick { frontend.send(:increment) }
          }
        }
      }
    }
  end

  class Frontend < DuoRuby::Frontend
    on :count do |value:|
      @model.value = value
    end

    def start
      @model = CounterModel.new
      connect
      CounterPage.render(model: @model, frontend: self)
    end
  end
end
