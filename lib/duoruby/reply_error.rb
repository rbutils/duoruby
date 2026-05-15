# frozen_string_literal: true

module DuoRuby
  class ReplyError < StandardError
    attr_reader :code, :details, :params

    def initialize(params)
      @params = params.transform_keys(&:to_sym)
      @code = @params[:code].to_s
      @details = @params[:details]
      super(@params[:message].to_s)
    end
  end
end
