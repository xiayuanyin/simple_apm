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

// JqueryDataTable自定义排序方法
jQuery.extend(jQuery.fn.dataTableExt.oSort, {
    "sec-pre": function (a) {
        var x = String(a).replace(/<[\s\S]*?>/g, "");    //去除html标记
        x = x.replace(/&amp;nbsp;/ig, "");                   //去除空格
        x = x.replace(/%/, "");                          //去除百分号
        if(x.indexOf('ms')>0){
            x = x.replace(/ms/, "");
            return parseFloat(x)/1000;
        }else if(x.indexOf('min')>0){
            x = x.replace(/min/, "");
            return parseFloat(x)*60;
        }else{
            x = x.replace(/min/, "");
            return parseFloat(x)
        }
    },
    "sec-asc": function (a, b) {                //正序排序引用方法
        return ((a < b) ? -1 : ((a > b) ? 1 : 0));
    },
    "sec-desc": function (a, b) {                //倒序排序引用方法
        return ((a < b) ? 1 : ((a > b) ? -1 : 0));
    }
});

