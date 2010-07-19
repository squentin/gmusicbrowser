var GmusicBrowserClient = Class.create({
    initialize: function() {
	
    },

    playpause: function() {
	new Ajax.Request("/playpause");
    },

    skip: function() {
	new Ajax.Request("/skip");
    },

    setVolume: function(volume) {
	new Ajax.Request("/volume", {
	    method: "post",
	    onSuccess: function(transport) {
		// TODO check return value, factor out said checking
	    }.bind(this),
	    onFailure: function(transport) {
		alert("holy shit problem setting volume");
	    }.bind(this),
	    parameters: {volume:volume}
	});
    },
});

var gmb = new GmusicBrowserClient();

var volume = new Control.Slider('seek_position', 'seek_slider', {
  axis:'horizontal',
  minimum: 0,
  maximum: 500,
  increment: 1,
  disabled: false, 
});

volume.options.onSlide = function(value) {
    console.log("whooooo: " + value);
    gmb.setVolume(value);
};

Event.observe('playpausebutton', 'click', function(event) {
    // TODO should be validating 200 OK
    gmb.playpause();
});

Event.observe('skipbutton', 'click', function(event) { 
    // TODO should be validating 200 OK
    gmb.skip();
});

