local newdecoder = require 'ejoysdk_lua.libs.lunajson.decoder'
local newencoder = require 'ejoysdk_lua.libs.lunajson.encoder'
local sax = require 'ejoysdk_lua.libs.lunajson.sax'
-- If you need multiple contexts of decoder and/or encoder,
-- you can require lunajson.decoder and/or lunajson.encoder directly.
return {
	decode = newdecoder(),
	encode = newencoder(),
	newparser = sax.newparser,
	newfileparser = sax.newfileparser,
}
