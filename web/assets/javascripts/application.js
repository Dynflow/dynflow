(function($) {
    $.fn.extend({
        postlink: function(options) {
            return this.each(function() {
                $(this).click(function(e) {
                    var frm = $("<form>");
                    frm.attr({'action':$(this).attr('href'), 'method': 'post'});
                    frm.appendTo("body");
                    frm.submit();
                    e.preventDefault();
                });
            });
        }
    });

    $(function() {
        $('.postlink').postlink();

        $('table.run-flow span.step-label').click(function (e) {
            var stepData = $(this).next('div.action');
            stepData.slideToggle();
        });
    });

})(jQuery);
