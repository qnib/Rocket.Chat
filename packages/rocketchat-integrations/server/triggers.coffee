triggers = {}

RocketChat.models.Integrations.find({type: 'webhook-outgoing'}).observe
	added: (record) ->
		channel = record.channel or '__any'
		triggers[channel] ?= {}
		triggers[channel][record._id] = record

	changed: (record) ->
		channel = record.channel or '__any'
		triggers[channel] ?= {}
		triggers[channel][record._id] = record

	removed: (record) ->
		channel = record.channel or '__any'
		delete triggers[channel][record._id]


ExecuteTriggerUrl = (url, trigger, message, room, tries=0) ->
	urlObj = URL.parse url

	console.log tries
	word = undefined
	if trigger.triggerWords?.length > 0
		for triggerWord in trigger.triggerWords
			if message.msg.indexOf(triggerWord) is 0
				word = triggerWord
				break

		# Stop if there are triggerWords but none match
		if not word?
			return

	data =
		token: trigger.token
		# team_id=T0001
		# team_domain=example
		channel_id: room._id
		channel_name: room.name
		timestamp: message.ts
		user_id: message.u._id
		user_name: message.u.username
		text: message.msg

	if word?
		data.trigger_word = word

	opts =
		data: data
		npmRequestOptions:
			rejectUnauthorized: !RocketChat.settings.get 'Allow_Invalid_SelfSigned_Certs'
			strictSSL: !RocketChat.settings.get 'Allow_Invalid_SelfSigned_Certs'
		headers:
			'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36'

	HTTP.call 'POST', url, opts, (error, result) ->
		console.log error, result
		if not result? or result.statusCode isnt 200
			if tries <= 6
				# Try again in 0.1s, 1s, 10s, 1m40s, 16m40s, 2h46m40s and 27h46m40s
				Meteor.setTimeout ->
					ExecuteTriggerUrl url, trigger, message, room, tries+1
				, Math.pow(10, tries+2)
			return

		# TODO process return and insert message if necessary



ExecuteTrigger = (trigger, message, room) ->
	for url in trigger.urls
		ExecuteTriggerUrl url, trigger, message, room


ExecuteTriggers = (message, room) ->
	if not room?
		return

	triggersToExecute = []

	if triggers[room._id]?
		triggersToExecute.push trigger for key, trigger of triggers[room._id]

	if triggers[room.name]?
		triggersToExecute.push trigger for key, trigger of triggers[room.name]

	if triggers.__any?
		triggersToExecute.push trigger for key, trigger of triggers.__any

	for triggerToExecute in triggersToExecute
		ExecuteTrigger triggerToExecute, message, room

	return message


RocketChat.callbacks.add 'afterSaveMessage', ExecuteTriggers, RocketChat.callbacks.priority.LOW