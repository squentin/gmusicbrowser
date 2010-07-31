var log = function(text) {
    if(window.console != undefined) {
        console.log(text);
    }
};

new Resource("song", {fields: ["id", "title", "artist", "length"]});

var GmusicBrowserClient = Class.create({
    initialize: function() {
	this.update_callbacks = new Array();
    },

    onUpdate: function(cb) {
	this.update_callbacks.push(cb);
    },

    update: function(json_status) {
	this.state_description = json_status.evalJSON();
	this.update_callbacks.each(function(cb) {
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

    play: function() {
	this.change({'playing': 1}, true);
    },
    
    pause: function() {
	this.change({'playing': 0}, true);
    },

    stop: function() {
	this.change({'playing':-1}, true);
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

    change: function(state_description, acceptNewState) {
	var thiz = this;
	new Ajax.Request("/player", {
	    method: "post",
	    onSuccess: function(response) {
		if(acceptNewState == true)
		    thiz.update(response.responseText);
	    }.bind(this),
	    onFailure: function(response) {
		alert("holy shit problem setting volume");
	    }.bind(this),
	    contentType:"application/json",
	    postBody: Object.toJSON(state_description)
	});
    },

    playing: function() {
	return this.state_description.playing;
    },

    setVolume: function(volume) {
	this.change({volume:volume}, false);
    },

    setPosition: function(position) {
	this.change({playposition:position}, false);
    },

    setPositionByRatio: function(position_ratio) {
	this.setPosition(position_ratio * this.state_description.current.length);
    }
});

var gmb = new GmusicBrowserClient();

// we *don't* want callbacks from the Sliders when we update them programmatically
var slider_lockout = false;

var volume = new Control.Slider('volume_position', 'volume_slider', {
  axis:'horizontal',
  minimum: 0,
  maximum: 500,
  increment: 1,
  disabled: false, 
});

var seek = new Control.Slider('seek_position', 'seek_slider', {
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
    slider_lockout = true;
    volume.setValue(state_description.volume / 100);
    var vol_ratio = state_description.playposition / state_description.current.length;
    seek.setValue(vol_ratio);
    slider_lockout = false;
}.bind(this);

gmb.onUpdate(do_update);

volume.options.onSlide = function(volume) {
    gmb.setVolume(volume);
};

volume.options.onChange = function(volume) {
    if(slider_lockout == false)
	gmb.setVolume(volume);
};

/* seek.options.onSlide = function(position_ratio) {
    gmb.setPositionByRatio(position_ratio);
}; uncomment for great hilarity. */

seek.options.onChange = function(position_ratio) {
    if(slider_lockout == false)
	gmb.setPositionByRatio(position_ratio);
};

Event.observe('playpausebutton', 'click', function(event) {
    switch(gmb.playing()) {
    case 0:
	gmb.play();
	break;
    case 1:
	gmb.pause();
	break;
    case -1:
	gmb.play();
	break;
    }
});

Event.observe('skipbutton', 'click', function(event) { 
    gmb.skip();
});

var receiveSong = function(song) {
    alert(song.title);
};

resources["song"].find(1, {}, receiveSong.bind(this));

gmb.getStateUpdate();

