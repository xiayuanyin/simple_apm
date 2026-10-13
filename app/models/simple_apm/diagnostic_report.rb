require 'uri'
require 'time'
require 'active_support/parameter_filter'

module SimpleApm
  class DiagnosticReport
    FILTERED = '[FILTERED]'.freeze
    SECRET_KEYS = /password|passwd|secret|token|authorization|cookie|session|api[_-]?key|credential|private[_-]?key/i

    def self.for_request(request, date:)
      new(date).with_query_date { |report| report.request_report(request) }
    end

    def self.for_action(action, date:)
      new(date).with_query_date { |report| report.action_report(action) }
    end

    def initialize(date)
      @date = date.to_s
      @generated_at = Time.now.utc.iso8601
      @sample_reports = {}
      @filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters + [SECRET_KEYS])
    end

    def with_query_date
      previous_date = Thread.current['apm_query_date']
      SimpleApm::RedisKey.query_date = @date
      yield self
    ensure
      Thread.current['apm_query_date'] = previous_date
    end

    def request_report(request)
      sqls = request.sqls
      http_requests = request.net_http_requests
      envelope('request').merge(
        request: {
          request_id: request.request_id, action_name: request.action_name,
          controller: request.controller, action: request.action, method: request.method,
          format: request.format, url: redact_url(request.url), host: request.host,
          remote_addr: request.remote_addr, started_at: request.started&.to_s,
          status: request.status, exception: redact_exception(request.exception)
        },
        timings: {
          total_seconds: number(request.during), database_seconds: number(request.db_runtime),
          view_seconds: number(request.view_runtime), external_http_seconds: number(request.net_http_during)
        },
        counters: {
          queries: integer(request.queries_count), cached_queries: integer(request.cached_queries_count),
          stored_sql_statements: sqls.length, stored_http_calls: http_requests.length
        },
        memory: { completed_mb: number(request.completed_memory), change_mb: number(request.memory_during) },
        sql: sqls.map { |sql| sql_report(sql) },
        http_calls: http_requests.map { |call| http_report(call) },
        limitations: [
          'SQL details contain all stored statements; statements at or below the configured SQL threshold are not stored.',
          'Status and SQL cache flags may be unavailable in older records. Request parameters/bodies and HTTP response status/bodies are not collected.',
          'Process memory is RSS, not allocations attributable solely to this request.'
        ],
        sql_storage_threshold_seconds: SimpleApm::Setting::SQL_CRITICAL_TIME.to_f
      )
    end

    def action_report(action)
      count = action.click_count.to_i
      limit = [SimpleApm::Setting::ACTION_SLOW_REQUEST_LIMIT.to_i, 0].max
      slow_samples = limit.zero? ? [] : SimpleApm::SlowRequest.list_by_action(action.name, limit)
      totals = {
        total_seconds: action.time.to_f, database_seconds: action.db_time.to_f,
        external_http_seconds: action.http_time.to_f, queries: action.queries_count.to_i,
        cached_queries: action.cached_queries_count.to_i
      }
      envelope('action').merge(
        action_name: action.name,
        metrics: {
          requests: count, totals: totals,
          averages: totals.transform_values { |value| count.positive? ? value.to_f / count : 0.0 },
          fastest_seconds: number(action.fast_time), slowest_seconds: number(action.slow_time)
        },
        samples: {
          fastest: sample(action.fast_id, action.fast_time),
          slowest: sample(action.slow_id, action.slow_time),
          retained_slow: slow_samples.map { |slow| sample(slow.request_id, slow.during) },
          retained_slow_limit: limit
        },
        limitations: [
          'Aggregates cover recorded requests on the query date. Details are retained for fastest, slowest and configured slow samples only; these are not representative of all requests.',
          'Stored request details may be unavailable. A missing sample is explicitly marked available=false.',
          'Historical request records and SQL/HTTP lists may outlive their current slow-sample ranking.'
        ]
      )
    end

    private

    def envelope(type)
      {
        schema_version: '1.0', type: type, application: SimpleApm::Setting::APP_NAME,
        query_date: @date, generated_at: @generated_at,
        units: { duration: 'seconds', memory: 'MB', memory_bytes_per_mb: 1_048_576 },
        redaction: 'Best effort: Rails filter_parameters and common credential keys; SQL string literals are filtered. Review remaining values before sharing.'
      }
    end

    def sample(id, duration)
      request = SimpleApm::Request.find(id) if id.present?
      {
        request_id: id, duration_seconds: number(duration), available: !request.nil?,
        report: request ? (@sample_reports[id] ||= request_report(request)) : nil
      }
    end

    def sql_report(sql)
      statement = redact_text(sql.sql).to_s
      statement = statement.gsub(/\$(\w*)\$.*?\$\1\$/m, "'#{FILTERED}'")
      statement = statement.gsub(/'(?:''|\\.|[^'\\])*'/m, "'#{FILTERED}'")
      binds = redact_binds(sql.value)
      {
        name: sql.name, statement: statement,
        full_statement: binds.present? ? "#{statement}\n\nParameters: #{binds.to_json}" : statement,
        binds: binds, cached: sql.respond_to?(:cached) ? sql.cached : nil,
        duration_seconds: number(sql.during), started_at: sql.started&.to_s,
        location: { filename: sql.filename, line: sql.line, method: sql.method }
      }
    end

    def http_report(call)
      {
        name: call.name, url: redact_url(call.url), host: call.host, path: redact_url(call.path),
        duration_seconds: number(call.during), started_at: call.started&.to_s,
        location: { filename: call.filename, line: call.line }
      }
    end

    def number(value)
      value.nil? ? nil : value.to_f
    end

    def integer(value)
      value.nil? ? nil : value.to_i
    end

    def redact_binds(value)
      if value.is_a?(Array)
        value.map do |bind|
          if bind.is_a?(Array) && bind.length == 2
            [bind[0], redact_text(@filter.filter_param(bind[0].to_s, bind[1]))]
          else
            redact_binds(bind)
          end
        end
      elsif value.is_a?(Hash)
        @filter.filter(value.deep_dup).transform_values { |item| redact_text(item) }
      else
        redact_text(value)
      end
    end

    def redact_exception(value)
      exception = value.is_a?(String) ? JSON.parse(value) : value
      redact_text(exception)
    rescue JSON::ParserError
      redact_text(value)
    end

    def redact_url(value)
      return nil if value.nil?

      url = URI.parse(value.to_s)
      url.userinfo = 'FILTERED' if url.userinfo
      if url.query
        parameters = URI.decode_www_form(url.query).map do |key, item|
          filter_key = key.gsub(/\[([^\]]*)\]/, '.\\1')
          [key, @filter.filter_param(filter_key, item)]
        end
        url.query = URI.encode_www_form(parameters).gsub('%5BFILTERED%5D', FILTERED)
      end
      redact_text(url.to_s)
    rescue URI::InvalidURIError, ArgumentError
      redact_text(value.to_s.gsub(%r{([a-z][a-z0-9+.-]*://)[^/\s?#]+@}i, '\\1FILTERED@'))
    end

    def redact_text(value)
      case value
      when Hash
        @filter.filter(value.deep_dup).transform_values { |item| redact_text(item) }
      when Array
        value.map { |item| redact_text(item) }
      when String
        text = value.gsub(%r{([a-z][a-z0-9+.-]*://)[^/\s?#]+@}i, '\\1FILTERED@')
        text = text.gsub(/\b(Bearer|Basic)\s+[A-Za-z0-9+\/=._-]+/i, "\\1 #{FILTERED}")
        text.gsub(/([\w.\[\]-]+)(["'`]?\s*[=:]\s*)('(?:''|[^'])*'|"(?:\\.|[^"])*"|[^\s&,;\)]+)/) do |match|
          key, separator, original = Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3)
          filtered = @filter.filter_param(key, original)
          mask = original.start_with?("'", '"') ? "#{original[0]}#{FILTERED}#{original[0]}" : FILTERED
          filtered == FILTERED ? "#{key}#{separator}#{mask}" : match
        end
      else
        value
      end
    end
  end
end
