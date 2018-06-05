module SimpleApm
  module ApplicationHelper
    def time_label(t, full = false)
      Time.parse(t).strftime("#{'%Y-%m-%d ' if full}%H:%M:%S") rescue ''
    end

    def sec_str(sec, force = nil)
      _sec = sec.to_f

      if force == 'min'
        return "#{(_sec / 60).to_f.round(1)} min"
      elsif force == 's'
        return "#{_sec.round(2)} s"
      elsif force == 'ms'
        return "#{(_sec * 1000).round} ms"
      end

      if (_sec / 60).to_i > 0
        "#{(_sec / 60).to_f.round(1)} min"
      elsif _sec.to_i > 0
        "#{_sec.round(2)} s"
      else
        "#{(_sec * 1000).round} ms"
      end
    end
  end
end
