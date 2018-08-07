module SimpleApm
  class NetHttp
    class << self
      def install
        Net::HTTP.class_eval do
          alias orig_request request unless method_defined?(:orig_request)

          def request(req, body = nil, &block)
            url = "http://#{@address}:#{@port}#{req.path}"
            ActiveSupport::Notifications.instrument "net_http.request", url: url, host: @address, path: req.path do
              @response = orig_request(req, body, &block)
            end
            @response
          end
        end
      end
    end
  end
end