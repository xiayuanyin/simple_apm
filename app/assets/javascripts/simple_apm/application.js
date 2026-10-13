// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file. JavaScript code in this file should be added after the last require_* statement.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require_tree .

(function ($) {
  'use strict';

  var config = JSON.parse(document.getElementById('apm-ui-config').textContent);
  window.SimpleApmUI = {
    tableOptions: function (overrides) {
      return $.extend(true, {language: config.table, pageLength: 25, processing: true}, overrides);
    }
  };

  $.extend($.fn.dataTableExt.oSort, {
    'sec-pre': function (value) {
      var exactSeconds = String(value).match(/data-seconds="([^"]+)"/);
      if (exactSeconds) return parseFloat(exactSeconds[1]) || 0;
      var text = String(value).replace(/<[^>]*>/g, '').replace(/&(?:amp;)?nbsp;/g, '').trim();
      var number = parseFloat(text) || 0;
      if (/ms\b/.test(text)) return number / 1000;
      if (/min\b/.test(text)) return number * 60;
      return number;
    },
    'sec-asc': function (a, b) { return a - b; },
    'sec-desc': function (a, b) { return b - a; }
  });
  $.fn.dataTable.ext.errMode = 'none';

  function fallbackCopy(text) {
    var input = document.createElement('textarea');
    input.value = text;
    input.setAttribute('readonly', '');
    input.style.position = 'fixed';
    input.style.top = '0';
    input.style.opacity = '0';
    // Keep the temporary input inside a modal so Bootstrap's focus trap allows selection.
    (document.querySelector('.modal.in .apm-modal-body') || document.body).appendChild(input);
    input.select();
    var copied = false;
    try { copied = document.execCommand('copy'); } catch (error) { copied = false; }
    input.remove();
    return copied;
  }

  $(function () {
    $('.select-apm-date select').on('change', function () { this.form.submit(); });
    $(document).on('submit', 'form[data-confirm]', function () {
      return window.confirm(this.getAttribute('data-confirm'));
    });
    $(document).on('click', 'a[data-confirm]', function () {
      return window.confirm(this.getAttribute('data-confirm'));
    });
    $(document).on('error.dt', 'table', function () {
      $(this).closest('.apm-panel').find('.apm-table-feedback').text(config.load_error);
    });
    $(document).on('xhr.dt', 'table', function (event, settings, data) {
      if (data) $(this).closest('.apm-panel').find('.apm-table-feedback').text('');
    });

    $(document).on('click', '.sql', function () {
      $('#sql-modal-text').text(this.textContent);
      $('#sql-modal .apm-copy-status').text('');
      $('#sql-modal').modal('show');
    });

    $(document).on('click', '[data-copy-target]', function () {
      var button = this;
      var target = document.getElementById(button.getAttribute('data-copy-target'));
      var text = target.value === undefined ? target.textContent : target.value;
      var status = $(button).closest('.apm-panel, .apm-modal-panel').find('.apm-copy-status');
      button.disabled = true;

      function finish(copied) {
        button.disabled = false;
        status.text(copied ? config.copied : config.copy_failed);
        if (copied) {
          button.focus();
        } else if (target.tagName === 'TEXTAREA') {
          $(target).closest('details').prop('open', true);
          target.focus();
          target.select();
        }
      }

      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(function () {
          finish(true);
        }, function () {
          finish(fallbackCopy(text));
        });
      } else {
        finish(fallbackCopy(text));
      }
    });
  });
})(jQuery);


