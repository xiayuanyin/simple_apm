class ErrorLogger
  class << self
    def log(e)
      @logger ||= Logger.new("#{Rails.root}/log/simple_apm_error.log")
      @logger.error(e)
    end
  end
end