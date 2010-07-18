var GmusicBrowserClient = Class.create({
    initialize: function() {
	
    },

    playpause: function() {
	new Ajax.Request("/playpause");
    },

    skip: function() {
	new Ajax.Request("/skip");
    }
});



var gmb = new GmusicBrowserClient();

Event.observe('playpausebutton', 'click', function(event) {
    // TODO should be validating 200 OK
    gmb.playpause();
});

Event.observe('skipbutton', 'click', function(event) { 
    // TODO should be validating 200 OK
    gmb.skip();
});

