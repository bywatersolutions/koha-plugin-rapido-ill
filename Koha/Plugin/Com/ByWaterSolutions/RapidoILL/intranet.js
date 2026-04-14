$(document).ready(function () {
    var $indicator = $('<li class="nav-item"><a class="nav-link" href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3AByWaterSolutions%3A%3ARapidoILL&method=tool&page=status" id="rapido-status-indicator" title="Rapido ILL: checking…"><i class="fa fa-circle" style="font-size:12px;color:#999"></i></a></li>');
    $("#toplevelmenu").append($indicator);
    var $icon = $indicator.find("i");
    var $link = $indicator.find("a");

    function checkStatus() {
        $.ajax({
            url: "/api/v1/contrib/rapidoill/status/api",
            dataType: "json",
            success: function (data) {
                if (data.status === "ok") {
                    $icon.css("color", "#2ecc40");
                    $link.attr("title", "Rapido ILL: operational");
                } else {
                    $icon.css("color", "#e74c3c");
                    var tip = "Rapido ILL: service disruption\n" +
                        "HTTP " + data.status_code + " since " + data.since + "\n" +
                        "Tasks delayed until " + data.delayed_until;
                    $link.attr("title", tip);
                }
            },
            error: function () {
                $icon.css("color", "#999");
                $link.attr("title", "Rapido ILL: status unavailable");
            }
        });
    }

    checkStatus();
    setInterval(checkStatus, 60000);
});
