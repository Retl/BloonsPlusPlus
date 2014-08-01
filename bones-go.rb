#!/usr/bin/env ruby
#
# bones
# by Jonathan Drain

require 'bones'

# I recommend that you change the name of your bot and the channels it joins to avoid
# conflict with other dicebots. Check with your network operator to ensure they allow bots.

# NB: As a security measure, some IRC networks prevent IRC bots from joining
# channels too quickly after connecting. Manually encourage it to join with this:
# /msg bones @@@join #channel

admin_name = "Retl"
your_bot_name = "Bloons"
server_to_join = "irc.canternet.org"
port = 6667
list_of_channels = ["#oddjobcourierooc"]
player_init_bonuses = {"Fighter" => 2, "Wizard" => 0, "FastRogue" => -3, "SlowRogue" => -1, "Cleric" => 0}

# NOTE: To join multiple networks, you can copy this file to create two Boneses.
# Alternatively, if you're familiar with Ruby, it should be straightforward. ('_')b

begin
  client = Bones::Client.new(your_bot_name, server_to_join, port, list_of_channels, admin_name, player_init_bonuses)
end
