// resource.js
// Copyright (c) 2009-2010 Andrew Clunis <aclunis@credil.org>
// Copyright (c) 2009-2010 CREDIL

// very simple Rails-esque REST library, vaguely inspired by Jester,
// ActiveRecord and ActiveResource.  Requires Prototype 1.6.

// MIT License

// belongs_to handles both inlines (:include on Base#to_json())
// and "kase_id" foreign-key fields.  However, such foreign_key fields
// will not trigger automatic downloading of the instance, and as such
// it will only work if the instance is in your cache already.
// (which is just fine, since requesting each one is almost certainly going to
// end up with very nasty and slow N+1 issues).
//
// it's really only useful for my use case (needed_songs has_many relationship
// inlined on the Playlist resource in Calliope).

// TODO: really need to be able to define resources by defining a
// class, rather just insantiating Resource with some arguments, and
// then using actual inheritance.  A la ActiveRecord.

// TODO: figure out what some more of the REST conventions are: if sending
// JSON, do I put it in a single field of form-encoded, or just raw,
// or should I support form-encoded at all, or...?

// TODO: has_many arrays should be preinitialized to []., so that they
// aren't undefined in the event of the resource getting updated
// with JSON that includes no array by that name.

// TODO: add "deep save" which will walk the tree of all owned
// subresources and save them if needed.  this will be useful for
// having subresources created and added to a brand new resource, and
// then saving them all at once.
// Convenient for UIs that wrap Resource instances where you want
// users to be able to create a structure of objects with depth and
// save them all at once, without needing to save the higher objects
// before the subobjects can be meaningfully created.

// TODO: even better, a inline deep save which will send JSON to the
// resource that had save() called on it that includes inline JSON of
// the subresources as configured.  (obviously the "_id" fields on the
// subresources would not be included as they would be normally).
// Much more efficient and atomic than the above approach, at least if
// your REST server supports it.

var resources = {};

var pluralize = function(str) {
    if(str.endsWith('y')) {
	return str.substring(0, str.length - 1) + "ies";
    } else if(str.endsWith('h')) {
	return str + "es";
    } else {
	return str + "s";
    }
};

var logError = function(e) {
    log("Error: " + e.message + ", stack: " + e.stack);
};

var Instance = Class.create({
    // resource: Resource object to which this Instance belongs,
    // hash: already-decoded JSON values for this Instance
    // id: ID if Resource already exists. If so, the instance is updated with the JSON.
    initialize: function(resource, id, json) {
	this.id = id;
	this.resource = resource;
	this.update_callbacks_sequence = 0;
	this.update_callbacks = new Hash();
	if(id == undefined) {
	    log("Creating new instance for new " + resource.name);
	    this.brand_new = true;
	} else {
	    log("Creating instance for existing " + resource.name + ", id: " + id);
	    this.brand_new = false;
	    this.update(json);
	    this.resource.registerInstance(this);
	}
    },

    /**
      * Register a callback to receive notification when this instance receives updates.
      * Returns an integer token you can use to unregister this callback in the future.
      */
    onUpdate: function(update_callback) {
	this.update_callbacks[++(this.update_callbacks_sequence)] = update_callback;
	return this.update_callbacks_sequence;
    },

    rmOnUpdate: function(update_callback_token) {
	if(!this.update_callbacks.keys().include(update_callback_token)) {
	    log("Hey! resource.js asked to remove an update callback that has not been added. token: " + update_callback_token);
	}
	this.update_callbacks.unset(update_callback_token);
    },

    // update this instance from JSON input
    update: function(json) {
	this.resource.fields.each(function(f) {
	    // FIXME -- this does not distinguish between missing or set to null.
	    //          as such, if a new JSON comes along with a field that
	    //          has been newly set to null, the old value will persist.
	    if(json[f] != undefined) {
		this[f] = json[f];
	    }
	}.bind(this));

	log("Now checking for belongs_to...");

	this.resource.belongs_to.each(function(bt) {
	    log("Processing belongs_to: " + bt.resource.name + ", with name: " + bt.field_name);
	    var field_name = undefined;
	    if(bt.field_name == undefined) {
		field_name = bt.resource.name;
	    } else {
		field_name = bt.field_name;
	    }
	    if(json[field_name] != undefined) {
		//                log("... which was set!");
		//                this[res.name] = new Instance(res, json[res.name]);
		this[field_name] = bt.resource.loadInstance(json[field_name].id, json[field_name]);
	    } else if(json[field_name + "_id"] != undefined) {
		// check for res.name + "_id" here.
		log("HAD AN NON-INLINE BELONGS TO");
		this[field_name] = bt.resource.loadInstance(json[field_name + "_id"], {});
	    }
	}.bind(this));

	this.resource.has_many.each(function(hm) {
	    var pluralized_name = pluralize(hm.name);
	    this[pluralized_name] = new Array();
	    log(this.resource.name + " Checking for has_many " + pluralized_name);
	    if(json[pluralized_name] != undefined) {
		$A(json[pluralized_name]).each(function(hm_item) {
		    //                    this[pluralized_name].push(new Instance(hm, hm_item));
		    this[pluralized_name].push(hm.loadInstance(hm_item.id, hm_item));
		}.bind(this));
	    } else {
		log("JSON does not include the relationship: " + pluralized_name);
	    }
	}.bind(this));

	this.update_callbacks.each(function(pair) {
	    pair.value();
	}.bind(this));
    },

    destroy: function(success_callback, failure_callback) {
	var req_opts = {
	    method: 'delete',
	    onSuccess: function(transport) {
		log("delete complete!");
		// TODO remove from the cache list to prevent any future id collisions
		success_callback();
	    }.bind(this),
	    onFailure: function(transport) {
		log("Problem deleting: " + this.resource.name + " #" + this.id);
		if(failure_callback != undefined) {
		    failure_callback();
		}
	    }.bind(this),
	    onException: function(e) {
		logError(e);
	    },
	    parameters: {authenticity_token: authenticity_token}
	};
	new Ajax.Request(this.resource.path(this.id), req_opts);
    },

    // save specific values only.
    // TODO factor out common bits with save()
    saveValues: function(values, success_callback, failure_callback) {
	var to_save = new Object();
	// scalar fields!
	this.resource.fields.each(function(f) {
	    if(values[f] != undefined) {
		to_save[f] = values[f];
	    }
	}.bind(this));
	to_save.id = this.id;
	// belongs_to!
	this.resource.belongs_to.each(function(bt) {
	    var field_name = undefined;
	    if(bt.field_name == undefined) {
		field_name = bt.resource.name;
	    } else {
		field_name = bt.field_name;
	    }
	    if(values[field_name] != undefined)
		to_save[field_name + "_id"] = values[field_name].id;
	}.bind(this));
	// no joy on has_many yet...

	var req_opts = {
	    method: 'put',
	    onSuccess: function(transport) {
		log("... save complete!");
		// TODO: iterate through values and set instance values to them
		json = transport.responseText.evalJSON(true);
		if(this.brand_new) {
		    this.id = parseInt(json.id);
		    this.resource.registerInstance(this);
		}
		this.brand_new = false;
		this.update(json);
		
		success_callback();
	    }.bind(this),
	    onFailure: function(transport) {
		log("... problem saving: " + this.resource.name + " #" + this.id);
		if(failure_callback != undefined) {
		    failure_callback();
		}
	    }.bind(this),
	    onException: function(transport, e) {
		logError(e);
	    },
	    parameters: {}
	};
	if(this.brand_new)
	    req_opts.method = "post";
	req_opts.parameters[this.resource.name] = Object.toJSON(to_save);
	req_opts.parameters.authenticity_token = authenticity_token;

	log("firing save req");
	new Ajax.Request(this.resource.path(this.id), req_opts);
    },

    // TODO does not support inline saving.
    save: function(success_callback, failure_callback) {
	var to_save = new Object();
	// scalar fields!
	this.resource.fields.each(function(f) {
	    to_save[f] = this[f];
	}.bind(this));
	// belongs_to!
	this.resource.belongs_to.each(function(bt) {
	    var field_name = undefined;
	    if(bt.field_name == undefined) {
		field_name = bt.resource.name;
	    } else {
		field_name = bt.field_name;
	    }
	    if(this[field_name] != undefined)
		to_save[field_name + "_id"] = this[field_name].id;
	}.bind(this));
	// no joy on has_many yet...

	var req_opts = {
	    method: 'put',
	    onSuccess: function(transport) {
		log("save complete!");
		json = transport.responseText.evalJSON(true);
		if(this.brand_new) {
		    this.id = parseInt(json.id);
		    this.resource.registerInstance(this);
		}
		this.brand_new = false;
		this.update(json);
	
		success_callback();
	    }.bind(this),
	    onFailure: function(transport) {
		log("Problem saving: " + this.resource.name + " #" + this.id);
		if(failure_callback != undefined) {
		    failure_callback();
		}
	    }.bind(this),
	    onException: function(e) {
		logError(e);
	    },
	    parameters: {}
	};
	if(this.brand_new)
	    req_opts.method = "post";
	// this is form_encoded, with one parameter containing the json.  does this involve any weird-ass
	// escaping/mangling that we want to avoid?  do we want to do it as raw JSON directly?
	req_opts.parameters[this.resource.name] = Object.toJSON(to_save);
	req_opts.parameters.authenticity_token = authenticity_token;

	log("firing save req");
	new Ajax.Request(this.resource.path(this.id), req_opts);
    }
});

var Resource = Class.create({
    initialize: function(name, options) {
	if(options == undefined)
	    options = {};
	this.instances = new Hash();

	this.has_many = new Array();
	this.belongs_to = new Array();
	log("Defining Resource \"" + name + "\"");
	this.name = name;
	this.options = options;
	if(options.has_many != undefined) {
	    log("has_many something...");
	    if(typeof(options.has_many) == "string") {
		this.hasMany(options.has_many);
	    } else {
		$A(options.has_many).each(function(rez) {
		    this.hasMany(rez);
		}.bind(this));
	    }
	}
	if(typeof(options.belongs_to) == "string") {
	    log("belongs_to something...");
	    this.belongsTo(options.belongs_to);
	}
	this.fields = $A(this.options.fields);
	resources[name] = this;
    },

    // TODO -- factor out belongs_to naming logic.
    belongsTo: function(resource, field_name) {
	if(typeof(resource) == "string") {
	    this.belongs_to.push({"resource":resources[resource], "field_name":field_name});
	} else {
	    this.belongs_to.push({"resource":resource, "field_name":field_name});
	}
    },

    // TODO -- factor out has_many naming logic.
    hasMany: function(resource) {
	if(typeof(resource) == "string") {
	    resource = resources[resource];
	}
	if(resource == undefined) {
	    log("Can't has_many of an undefined resource!");
	    return;
	}
	log(this.name + " has_many " + pluralize(resource.name));
	this.has_many.push(resource);
    },

    path: function(id, custom_action) {
	if(id != undefined) {
	    return this.basePath() + "/" + id + ".json";
	}
	else {
	    if(custom_action == undefined)
		return this.basePath() + ".json";
	    else
		return this.basePath() + "/" + custom_action + ".json";
	}
    },

    basePath: function() {
	return "/" + pluralize(this.name);
    },

    registerInstance: function(instance) {
	this.instances.set(parseInt(instance.id), instance);
    },

    getInstanceById: function(instance_id) {
	var instance = this.instances.get(parseInt(instance_id));

	return instance;
    },

    // this is to be called when there's JSON available for a resource.
    // it will retrieve the existing instance from the cache and update it,
    // otherwise, it will create a new one.
    // id may be given as either an integer or a string.
    loadInstance: function(instance_id, update_json) {
	instance_id = parseInt(instance_id);
	var instance = this.getInstanceById(instance_id);
	//        log("Getting instance of " + this.name + " by ID: " + instance_id);
	if(instance == undefined) {
	    //          log("Does not already exist, creating a new one!");
	    instance = new Instance(this, instance_id, update_json);
	    //            this.registerInstance(instance);
	} else {
	    //        log("... which did exist!");
	    instance.update(update_json);
	}
	return instance;
    },

    // id:         Either the ID number of the resource you want to find,
    //             or "all" to use ActiveRecord#Base.find(:all)-like
    //             behaviour.
    // parameters: Used like ActiveRecord conditions, but are basically
    //             just extra parameters added to the request.
    //             Check out my Base#find_by_params() method for making this seamless-ish.
    // callback:   This API is asynchronous, unlike
    //             ActiveRecord/ActiveResource.  This is the callack that
    //             we should call when we get the results.
    // options:    various options are available, in ActiveRecord-style.
    //             action: when finding "all", this is appended to the
    //                     resource base path as an extra path element
    //                     ("/kases/my_action.json" instead of
    //                     "/kases.json")
    find: function(id, parameters, callback, options) {
	if(options == undefined)
	    options = {};
	if (id == "all") {
	    var path = this.path(options["action"]);
	    log("Finding all, path is: " + path);
	    return new Ajax.Request(path, {
		method: "get",
		onSuccess: function(transport) {
		    this.foundAll(transport.responseText, callback);
		}.bind(this),
		onFailure: function(transport) {
		    log("Problem looking up all results, with parameters: " + parameters);
		}.bind(this),
		onException: function(e) {
		    logError(e);
		},
		parameters: parameters
	    });
	} else {
	    var path = this.path(id);
	    log("Finding first, path is: " + path);
	    return new Ajax.Request(path, {
		method: 'get',
		onSuccess: function(transport) {
		    // log("complete: " + transport.responseText);
		    this.foundOne(transport.responseText, callback);
		}.bind(this),
		onFailure: function(transport) {
		    log("Problem looking up " + this.name + " #" + id);
		},
		onException: function(transport, e) {
		    logError(e);
		},
		parameters: parameters
	    });
	}
    },

    // keep in mind that, like ActiveRecord, "all" means process many
    // results as a list, and not necessarily existing instances of
    // the Resource.
    foundAll: function(json_text, callback) {
	var json = json_text.evalJSON(true);
	log("found all (many results), " + json.length + " in total.");
	var pluralized_name = pluralize(this.name);
	var results = new Array();
	$A(json).each(function(item_json) {
	    log("... " + item_json.id);
	    results.push(this.loadInstance(item_json.id, item_json));
	}.bind(this));
	callback(results);
    },

    foundOne: function(json_text, callback) {
	var json = json_text.evalJSON(true);
	this.foundOneDecoded(json, callback);
    },

    foundOneDecoded: function(json, callback) {
	log("foundone: " + json.id);
	var instance = this.loadInstance(json.id, json);
	log("instance instantiated!");
	callback(instance);
    },

    // N.B. unlike AR's create, this one does not save right away!
    create: function() {
	return new Instance(this, undefined, undefined);
    }
});
