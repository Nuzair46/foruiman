# frozen_string_literal: true

module Foruiman
  class Error < StandardError
  end
end

require_relative "foruiman/version"
require_relative "foruiman/procfile"
require_relative "foruiman/env"
require_relative "foruiman/engine"
