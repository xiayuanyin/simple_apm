require 'net/http'
module SimpleApm
  class NetHttp
    class << self
      def install
        Net::HTTP.class_eval do
          alias origin_request_apm request unless method_defined?(:origin_request_apm)
          alias origin_do_start_apm do_start unless method_defined?(:origin_do_start_apm)

          def do_start
            Thread.current[:injection_net_http_request_start_time] = Time.now
            origin_do_start_apm
          end

          def request(req, body = nil, &block)
            url = if @port == '80'
                    "http://#{@address}#{req.path}"
                  elsif @port == '443'
                    "https://#{@address}#{req.path}"
                  else
                    "http://#{@address}:#{@port}#{req.path}"
                  end
            payload = {
                real_start_time: Thread.current[:injection_net_http_request_start_time],
                url: url, host: @address, path: req.path
            }
            if started?
              ActiveSupport::Notifications.instrument 'net_http.request', payload do
                @response = origin_request_apm(req, body, &block)
              end
            else
              # 去connect
              @response = origin_request_apm(req, body, &block)
            end
            @response
          end
        end
      end
    end
  end
end