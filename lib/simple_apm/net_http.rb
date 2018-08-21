module SimpleApm
  class NetHttp
    class << self
      def install
        Net::HTTP.class_eval do
          alias orig_request_apm request unless method_defined?(:orig_request)

          def request(req, body = nil, &block)
            url = if @port == '80'
                    "http://#{@address}#{req.path}"
                  elsif @port == '443'
                    "https://#{@address}#{req.path}"
                  else
                    "http://#{@address}:#{@port}#{req.path}"
                  end
            # 会调用两次(HTTParty)
            if started?
              ActiveSupport::Notifications.instrument "net_http.request", url: url, host: @address, path: req.path do
                @response = orig_request_apm(req, body, &block)
              end
            else
              # 去connect
              @response = orig_request_apm(req, body, &block)
            end
            @response
          end
        end
      end
    end
  end
end