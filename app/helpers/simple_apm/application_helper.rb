module SimpleApm
  module ApplicationHelper
    def duration_percent(part, total)
      return 0 if total.to_f <= 0
      [[(part.to_f / total.to_f * 100).round(1), 0].max, 100].min
    end

    def table_language
      {
        search: t('simple_apm.table.search'),
        lengthMenu: t('simple_apm.table.length_menu'),
        info: t('simple_apm.table.info'),
        infoEmpty: t('simple_apm.table.info_empty'),
        infoFiltered: t('simple_apm.table.info_filtered'),
        zeroRecords: t('simple_apm.table.zero_records'),
        emptyTable: t('simple_apm.table.empty'),
        loadingRecords: t('simple_apm.table.loading'),
        processing: t('simple_apm.table.processing'),
        paginate: {
          first: t('simple_apm.table.first'), last: t('simple_apm.table.last'),
          next: t('simple_apm.table.next'), previous: t('simple_apm.table.previous')
        },
        aria: {sortAscending: t('simple_apm.table.sort_ascending'), sortDescending: t('simple_apm.table.sort_descending')}
      }
    end

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
