module SimpleApm
  module ApplicationHelper
    def time_label(t, full = true)
      Time.parse(t).strftime("%Y-%m-%d#{' %H:%M:%S' if full}") rescue ''
    end
  end
end
