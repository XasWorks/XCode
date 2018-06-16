
require_relative 'HTTPCore.rb'
require 'mqtt/sub_handler'

module Xasin
module Telegram
	module MQTT
		class Server
			attr_accessor :usernameList

			def initialize(httpCore, mqtt)
				if(httpCore.is_a? Telegram::HTTPCore)
					@httpCore = httpCore;
				else
					@httpCore = Telegram::HTTPCore.new(httpCore);
				end
				@httpCore.attach_receptor(self);

				@mqtt = mqtt;

				# Hash {username => ChatID}
				@usernameList 	= Hash.new();
				# Hash {ChatID => {GroupID => MessageID}}
				@groupIDList 	= Hash.new do |hash, key|
					hash[key] = Hash.new;
				end

				setup_mqtt();
			end

			def _process_inline_keyboard(keyboardLayout, gID)
				return nil unless (keyboardLayout.is_a? Array or keyboardLayout.is_a? Hash)
				return nil unless gID

				keyboardLayout = [keyboardLayout] unless(keyboardLayout[0].is_a? Array);
				outData = Array.new();

				keyboardLayout.each do |row|
					newRow = Array.new();

					row.each do |key, val|
						cbd = {i: gID, k: (val or key)};
						newRow << {text: key, callback_data: cbd.to_json}
					end
					outData << newRow;
				end

				return {inline_keyboard: outData};
			end

			# Processes messages received through MQTT
			# It takes care of setting a few good defaults (like parse_mode),
			# deletes any old messages of the same GroupID (if requested),
			# and stores the new Message ID for later processing
			# @param data [Hash] The raw "message" object received from the Telegram API
			# @param uID [Integer,String] The user-id as received from the MQTT Wildcard.
			#   Can be a username defined in @usernameList
			def _handle_send(data, uID)
				# Resolve a saved Username to a User-ID
				uID = @usernameList[uID] if(@usernameList.key? uID)
				return if (uID = uID.to_i) == 0;

				begin
					data = JSON.parse(data, symbolize_names: true) if data.is_a? String
				rescue
					# Allow for pure-text to be sent (easier on the ESPs)
					data = {text: data}
				end

				if(gID = data[:gid])
					if(data[:replace])
						_handle_delete(gID, uID)
					elsif(data[:overwrite] and @groupIDList[uID][gID])
						_handle_edit(data, uID);
						return;
					end
				end

				outData = {
					chat_id: 	uID,
					parse_mode: (data[:parse_mode] or "Markdown"),
					text:			data[:text]
				}

				if(ilk = data[:inline_keyboard] and data[:gid])
					outData[:reply_markup] = _process_inline_keyboard(ilk, data[:gid]);
				end

				reply = @httpCore.perform_post("sendMessage", outData);
				return unless reply[:ok]

				# Check if this message has a grouping ID
				if(gID = data[:gid])
					# Save this grouping ID
					@groupIDList[uID][gID] = reply[:result][:message_id];
				end
			end

			def _handle_edit(data, uID)
				# Resolve a saved Username to a User-ID
				uID = @usernameList[uID] if(@usernameList.key? uID)
				return if (uID = uID.to_i) == 0;

				begin
					data = JSON.parse(data, symbolize_names: true) if data.is_a? String

					# Fetch the target Message ID
					return unless mID = @groupIDList[uID][data[:gid]]

					outData = {
						chat_id: uID,
						message_id: mID,
					};

					if(data[:inline_keyboard] and data[:gid])
						outData[:reply_markup] = _process_inline_keyboard(data[:inline_keyboard], data[:gid]);
					end

					if(data[:text])
						outData[:text] = data[:text];
						# Send the POST request editing the message text
						@httpCore.perform_post("editMessageText", outData);
					else
						@httpCore.perform_post("editMessageReplyMarkup", outData);
					end
				rescue
				end
			end

			def _handle_delete(data, uID)
				# Resolve a saved Username to a User-ID
				uID = @usernameList[uID] if(@usernameList.key? uID)
				return if (uID = uID.to_i) == 0;

				# Fetch the real message ID held by a grouping ID
				return unless mID = @groupIDList[uID][data]
				@groupIDList[uID].delete(data);

				@httpCore.perform_post("deleteMessage", {chat_id: uID, message_id: mID});
			end

			def setup_mqtt()
				@mqtt.subscribe_to "Telegram/+/Send" do |data, tSplit|
					_handle_send(data, tSplit[0]);
				end

				@mqtt.subscribe_to "Telegram/+/Edit" do |data, tSplit|
					_handle_edit(data, tSplit[0])
				end

				@mqtt.subscribe_to "Telegram/+/Delete" do |data, tSplit|
					_handle_delete(data, tSplit[0])
				end

				@mqtt.subscribe_to "Telegram/+/Release" do |data, tSplit|
					# Resolve a saved Username to a User-ID
					uID = tSplit[0];
					uID = @usernameList[uID] if(@usernameList.key? uID)
					uID = uID.to_i;

					# Delete the stored GID key
					@groupIDList[uID].delete(data);
				end
			end

			def handle_packet(packet)
				if(msg = packet[:message])
					uID = msg[:chat][:id];
					if(newUID = @usernameList.key(uID))
						uID = newUID
					end

					data = Hash.new();
					return unless(data[:text] = msg[:text])

					if(replyMSG = msg[:reply_to_message])
						data[:reply_gid] = @groupIDList[uID].key(replyMSG[:message_id]);
					end

					if(data[:text] =~ /^\//)
						@mqtt.publish_to "Telegram/#{uID}/Command", data.to_json;
					elsif(data[:reply_gid])
						@mqtt.publish_to "Telegram/#{uID}/Reply", data.to_json;
					else
						@mqtt.publish_to "Telegram/#{uID}/Received", data.to_json;
					end
				end

				if(msg = packet[:callback_query])
					@httpCore.perform_post("answerCallbackQuery", {callback_query_id: msg[:id]});

					uID = msg[:message][:chat][:id];
					if(newUID = @usernameList.key(uID))
						uID = newUID
					end

					return unless /(\S+):(\S+)/ =~ msg[:data]
					begin
						data = JSON.parse(msg[:data], symbolize_names: true);

						data = {
							gid:  data[:i],
							key: data[:k],
						}

						if(data[:key] =~ /^\//)
							@mqtt.publish_to "Telegram/#{uID}/Command", {text: data[:key]}.to_json
						end
						@mqtt.publish_to "Telegram/#{uID}/KeyboardPress", data.to_json
					rescue
					end
				end
			end
		end
	end
end
end
