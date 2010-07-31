var log = function(text) {
    if(window.console != undefined) {
        console.log(text);
    }
};

// used in resource.js's rails-inspired XSS protection.  not implemented on the server yet...
var authenticity_token = "fnubbbbbiats";

new Resource("song", {fields: ["id", "title", "artist", "length", "rating"]});

var TransportUI = Class.create({
    initialize: function(client) {
	this.client = client;
	// we *don't* want callbacks from the Sliders when we update them programmatically
	this.slider_lockout = false;

	this.volume = new Control.Slider('volume_position', 'volume_slider', {
	    axis:'horizontal',
	    minimum: 0,
	    maximum: 500,
	    increment: 1,
	    disabled: false, 
	});

	this.seek = new Control.Slider('seek_position', 'seek_slider', {
	    axis:'horizontal',
	    minimum: 0,
	    maximum: 500,
	    increment: 1,
	    disabled: false, 
	});

	this.client.onUpdate(this.doUpdate.bind(this));

	this.volume.options.onSlide = function(volume) {
	    this.client.setVolume(volume);
	}.bind(this);

	this.volume.options.onChange = function(volume) {
	    if(slider_lockout == false)
		this.client.setVolume(volume);
	}.bind(this);

	/* seek.options.onSlide = function(position_ratio) {
	    client.setPositionByRatio(position_ratio);
	    }; uncomment for great hilarity. */

	this.seek.options.onChange = function(position_ratio) {
	    if(slider_lockout == false)
		this.client.setPositionByRatio(position_ratio);
	}.bind(this);

	Event.observe('playpausebutton', 'click', function(event) {
	    switch(this.client.playing()) {
	    case 0:
		this.client.play();
		break;
	    case 1:
		this.client.pause();
		break;
	    case -1:
		this.client.play();
		break;
	    }
	}.bind(this));

	Event.observe('skipbutton', 'click', function(event) { 
	    this.client.skip();
	}.bind(this));
    },

    doUpdate: function(state_description, current_song) {
	// TODO we may not get all fields here, only update ones that actually are

	$('current_song_title').innerHTML = current_song.title.escapeHTML();
	$('current_song_artist').innerHTML = current_song.artist.escapeHTML();
	if(state_description.playing == 1) {
	    $('playpausebutton').innerHTML = "Pause";
	} else {
	    $('playpausebutton').innerHTML = "Play";
	}
	slider_lockout = true;
	this.volume.setValue(state_description.volume / 100);
	var vol_ratio = state_description.playposition / current_song.length;
	this.seek.setValue(vol_ratio);
	this.slider_lockout = false;
    }
});

var GmusicBrowserClient = Class.create({
    initialize: function() {
	this.update_callbacks = new Array();
    },

    onUpdate: function(cb) {
	this.update_callbacks.push(cb);
    },

    update: function(json_status) {
	this.state_description = json_status.evalJSON();
	resources["song"].foundOneDecoded(this.state_description.current, function(song) {
	    this.current_song = song;
	}.bind(this));
	this.update_callbacks.each(function(cb) {
	    cb(this.state_description, this.current_song);
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
	    },
	    onException: function(response, exception) {
		log("Problem getting status update: " + exception.message + ", stack: " + exception.stack);
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
	    },
	    onException: function(response, e) {
		alert(e);
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
	    onException: function(response, e) {
		alert(e);
	    },
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

var transport = new TransportUI(gmb);

// var receiveSong = function(song) {
//     alert(song.title);
//     log("attempting to save...");
//     song.save_values({artist:"Benn Jordan"}, function() {
// 	alert("saved nonsense successfully");
//     }.bind(this), function() {
// 	alert("some sort of fuckup while saving!");
//     }.bind(this));
// };

// resources["song"].find(1, {}, receiveSong.bind(this));

gmb.getStateUpdate();

