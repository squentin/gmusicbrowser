var GmusicBrowserClient = Class.create({
    initialize: function() {
	this.update_callbacks = new Array();
    },

    onUpdate: function(cb) {
	this.update_callbacks.push(cb);
    },

    update: function(json_status) {
	this.update_callbacks.each(function(cb) {
	    this.state_description = json_status.evalJSON();
	    cb(this.state_description);
	}.bind(this));
    },

    getStateUpdate: function() {
	// is there a better way to do this? scoping isn't quite what I expect evidently.
	var thiz = this;
	new Ajax.Request("/player", {
	    method: 'get',
	    onSuccess: function(response) {
		thiz.update(response.responseText);
	    },
	    onFailure: function(response) {
		alert("holy crap problem play/pause'ing");
	    }
	});
    },

    playpause: function() {
	// is there a better way to do this? scoping isn't quite what I expect evidently.
	var thiz = this;
	new Ajax.Request("/playpause", {
	    method: 'post',
	    onSuccess: function(response) {
		thiz.update(response.responseText);
	    },
	    onFailure: function(response) {
		alert("holy crap problem play/pause'ing");
	    }
	});
    },

    skip: function() {
	var thiz = this;
	new Ajax.Request("/skip", {
	    method: 'post',
	    onSuccess: function(response) {
		thiz.update(response.responseText);
	    },
	    onFailure: function(response) {
		alert("holy crap problem skipping");
	    }
	});
    },

    setVolume: function(volume) {
	new Ajax.Request("/volume", {
	    method: "post",
	    onSuccess: function(response) {
		// TODO check return value, factor out said checking
	    }.bind(this),
	    onFailure: function(response) {
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

var do_update = function(state_description) {
    // TODO we may not get all fields here, only update ones that actually are.
    $('current_song_title').innerHTML = state_description.current.title.escapeHTML();
    $('current_song_artist').innerHTML = state_description.current.artist.escapeHTML();
    if(state_description.playing == 1) {
	$('playpausebutton').innerHTML = "Pause";
    } else {
	$('playpausebutton').innerHTML = "Play";
    }
    volume.setValue(state_description.volume / 100);
}.bind(this);

gmb.onUpdate(do_update);

volume.options.onSlide = function(value) {
    gmb.setVolume(value);
};

Event.observe('playpausebutton', 'click', function(event) {
    gmb.playpause();
});

Event.observe('skipbutton', 'click', function(event) { 
    gmb.skip();
});

gmb.getStateUpdate();