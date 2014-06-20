#!/usr/bin/env ruby
#
# bones v0.03
# by Jonathan Drain http://d20.jonnydigital.com/roleplaying-tools/dicebot
# (run "bones-go.rb" first)
#
# NB: As a security measure, some IRC networks prevent IRC bots from joining
# channels too quickly after connecting. Solve with this:
# /msg bones @@@join #channel

require 'socket'
require 'strscan'
require 'dicebox'
require 'chargen'

module Bones
  class Client # an "instance" of bones; generally only one
    def initialize(nick, server, port, channels, admin, player_init_bonuses)
      @running = true
      
      @nick = nick
      @server = server # one only
      @port = port
      @channels = channels
      @admin = "Retl"
      @player_init_bonuses = player_init_bonuses

      connect()
      run()
    end

    def connect
      @connection = Connection.new(@server, @port)
      
      @connection.speak "NICK #{@nick}"
      @connection.speak "USER #{@nick} bones * :Bones++ Dicebot: https://github.com/injate/BonesPlusPlus/"
      # This needs some work, faking the client port (54520) right now.
      # http://www.team-clanx.org/articles/socketbot-ident.html
      @connection.speak "IDENT 54520, #{@port} : USERID : UNIX : #{@nick}"

      # TODO: fix join bug
      join(@channels)
    end

    def join(channels)
      channels.each do |channel|
        # join channel
        @connection.speak "JOIN #{channel}"
        puts "Joining #{channel}"
      end
    end
    
    def join_quietly(channels)
      channels.each do |channel|
        # join channel
        @connection.speak("JOIN #{channel}", true)
      end
    end
    
    def run # go
      # stay connected
      # handle replies

      while @running
        while @connection.disconnected? # never give up reconnect
          sleep 10
          connect()
        end
        
        handle_msg (@connection.listen)
      end
    end
    
    def handle_msg(msg)
      case msg
        when nil
          #nothing
        when /END OF MESSAGE/ # For irc.gamesurge.net joining ASAP, the 1st join happens too early to work on some servers.
          join_quietly(@channels)
        when /^PING (.+)$/
          @connection.speak("PONG #{$1}", true) # PING? PONG!
          # TODO: Check if channels are joined before attempting redundant joins
          join_quietly(@channels)
        when /^:/ # msg
          message = Message.new(msg)
          respond(message)
        else
          puts "RAW>> #{msg}"
          #nothing
      end
    end
    
    def respond(msg)
      # msg :name, :hostname, :mode, :origin, :privmsg, :text
      if msg.name =~ /#{@admin}/ && msg.text =~ /^#{@nick}, quit/i
        quit(msg.text)
      end
     
      if msg.text =~ /^#{@nick}(:|,*) ?(\S+)( (.*))?/i
        prefix = @nick
        command = $2.downcase
        unless $4.nil? #optional args, downcase errors on nil
          args = $4.downcase
        end
        # do command - switch statement or use a command handler class
        c = command_handler(prefix, command, args)
        reply(msg, c) if c
      elsif msg.text =~ /^@@@join (#.*)/
        join $1.to_s
      elsif msg.text == "hay"
        reply(msg, "hay :v")
      elsif msg.text == "plot"
        reply(msg, handle_booty)
      elsif msg.text == "butts"
        reply(msg, handle_booty)
      elsif msg.text == "chargen"
      	for lines in chargen().split("\n")
      		reply(msg, lines)
      	end
      elsif msg.text =~ /^(!|@)(\S+)( (.*))?/
        prefix = $1
        command = $2
        args = $4
        #do command
        c = command_handler(prefix, command, args)
        reply(msg, c) if c
      elsif msg.text =~ /^(\d*#)?(\d+)d(\d+)/
        # DICE HANDLER
        dice = Dicebox::Dice.new(msg.text)
        begin
          d = dice.roll
          if (d.length < 350)
            reply(msg, d)
          else
            reply(msg, "I don't have enough dice to roll that!")
          end
        rescue Exception => e
          puts "ERROR: " + e.to_s
          reply(msg, "I don't understand...")
        end
      end
    end
    
    def command_handler(prefix, command, args)
      c = CommandHandler.new(prefix, command, args, @player_init_bonuses)
      return c.handle
    end

    def reply(msg, message) # reply to a pm or channel message
      if msg.privmsg
        @connection.speak "#{msg.mode} #{msg.name} :#{message}"
      else
        @connection.speak "#{msg.mode} #{msg.origin} :#{msg.name}, #{message}"
      end
    end
    
    def pm(person, message)
      @connection.speak "PRIVMSG #{person} :#{message}"
    end
    
    def say(channel, message)
      pm(channel, message) # they're functionally the same
    end
    
    def notice(person, message)
      @conection.speak "NOTICE #{person} :#{message}"
    end

    def quit(message)
      @connection.speak "QUIT :#{message}"
      @connection.disconnect
      @running = false;
    end
    
    #FoE-specific BEGIN
    def handle_booty
    
      booty = []
      booty << "http://derpibooru.org/523772"
      booty << "http://derpibooru.org/105657"
      booty << "http://derpibooru.org/508212"
      booty << "http://derpibooru.org/417304"
      booty << "http://derpibooru.org/105675"
      booty << "http://derpibooru.org/4321"
      booty << "http://derpibooru.org/104625"
      booty << "http://derpibooru.org/194027"
      booty << "http://derpibooru.org/558949"
      booty << "http://derpibooru.org/558949" #9
      booty << "http://derpibooru.org/190416"
      booty << "http://derpibooru.org/161592"
      booty << "http://derpibooru.org/162805"
      booty << "http://derpibooru.org/197077"
      booty << "http://derpibooru.org/290177"
      booty << "http://derpibooru.org/514504"
      booty << "http://derpibooru.org/521245"
      booty << "http://derpibooru.org/564328"
      booty << "http://derpibooru.org/579481"
      booty << "http://derpibooru.org/588674" #19
      booty << "http://derpibooru.org/596565"
      booty << "http://derpibooru.org/616549"
      booty << "http://derpibooru.org/621712"
      
      
      selection = rand(booty.length)
      
      #result = selection.to_s + ": " + booty[selection]
      result = booty[selection]
      return result
    end
    
    #FoE-specific END
  end

  class Message
    attr_accessor :name, :hostname, :mode, :origin, :privmsg, :text
    
    def initialize(msg)
      parse(msg)
    end
    
    def parse(msg)
      # sample messages:
      # :JDigital!~JD@86.156.2.220 PRIVMSG #bones :hi
      # :JDigital!~JD@86.156.2.220 PRIVMSG bones :hi
      
      # filter out bold and colour
      # feature suggested by KT
      msg = msg.gsub(/\x02/, '') # bold
      msg = msg.gsub(/\x03(\d)?(\d)?/, '') # colour

      case msg
        when nil
          puts "heard nil? wtf"
        when /^:(\S+)!(\S+) (PRIVMSG|NOTICE) ((#?)\S+) :(.+)/
          @name = $1
          @hostname = $2
          @mode = $3
          @origin = $4
          if ($5 == "#")
            @privmsg = false
          else
            @privmsg = true
          end
          @text = $6.chomp
          print()
      end
    end

    def print
      puts "[#{@origin}|#{@mode}] <#{@name}> #{@text}"
    end
  end
  
  class Connection # a connection to an IRC server; only one so far
    attr_reader :disconnected

    def initialize(server, port)
      @server = server
      @port = port
      @disconnected = false
      connect()
    end
    
    def connect
      # do some weird stuff with ports
      @socket = TCPSocket.open(@server, @port)
      puts "hammer connected!"
      @disconnected = false
    end

    def disconnected? # inadvertently disconnected
      return @socket.closed? || @disconnected
    end

    def disconnect
      @socket.close
    end

    def speak(msg,quietly = nil)
      begin
        if quietly != true
          puts("spoke>> " + msg)
        end
        @socket.write(msg + "\n")
      rescue Errno::ECONNRESET
        @disconnected = true;
      end 
    end
  
    def listen  # poll socket for lines. luckily, listen is sleepy
      sockets = select([@socket], nil, nil, 1)
      if sockets == nil
        return nil
      else
        begin
          s = sockets[0][0] # read from socket 1
          
          if s.eof?
            @disconnected = true
            return nil
          end
          
          msg = s.gets
          
        rescue Errno::ECONNRESET
          @disconnected = true
          return nil
        end
      end
    end
  end

  class CommandHandler
    def initialize(prefix, command, args, player_init_bonuses)
      @prefix = prefix
      @command = command
      @args = args
      @args.strip if @args
      @player_init_bonuses = player_init_bonuses
    end
    
    def handle
      case @command
	when "init", "initiative"
	  result = handle_init
        when "chargen"
          result = handle_chargen
        when "rules", "rule"
          result = handle_rules
        when "help"
          result = handle_help
        else
          result = nil
        #end
      end
      return result
    end
    
    def handle_chargen
      set = []
      6.times do
        roll = []
        4.times do
          roll << rand(6)+1
        end
        roll = roll.sort
        total = roll[1] + roll[2] + roll[3]
        set << total
      end
      
      if set.sort[5] < 13
        return handle_chargen
      end
      
      return set.sort.reverse.join(", ")
    end
    
    def handle_rules
      case @args
        when "chargen", "pointsbuy", "pointbuy", "point buy", "points buy", "houserules", "house rules"
          result = "Iron Heroes style pointbuy, 26 points. "
          result += "Ability scores start at 10. Increments cost 1pt up to 15, 2pts up to 17, "
          result += "and 4pts up to 18, before racial modifiers. "
          result += "You may drop any one 10 to an 8 and spend the two points elsewhere. "
          result += "You may have up to one flaw and two traits."
        else
          result = nil
        #end
      end
      return result
    end
    
    def handle_help
      result = "Roll dice in the format '1d20+6'. Multiple sets as so: '2#1d20+6'. "
      result += "Rolls can be followed with a comment as so: '1d20+6 attack roll'. "
      result += "Separate multiple rolls with a semicolon, ';'. "
      result += "Features: Can add and subtract multiple dice, shows original rolls, "
      result += "high degree of randomness (uses a modified Mersenne Twister with a period of 2**19937-1)."
      result += "Bugs: must specify the '1' in '1d20'."
      return result
    end

    def handle_join(client,channel)
      client.join(channel)
    end

    def handle_init()
      players = @player_init_bonuses
      playerRolls = Hash.new
      playerFullRolls = Hash.new
      results = '| '
      resultsFull = '| '
      players.each { |player,bonus|
        init = Dicebox::Dice.new("1d10+"+bonus.to_s())
        initroll = init.roll
        playerFullRolls[player] = initroll
        /^[^:]*: (-?\d+)/ =~ initroll 
        playerRolls[player] = Regexp.last_match(1).to_i(10)
      }
      playerRolls = playerRolls.sort {|a,b| a[0]<=>b[0]}
      playerRolls = playerRolls.sort {|a,b| a[1]<=>b[1]}
      playerRolls.each { |player,roll|
        results += "#{player}: #{roll} | "
        resultsFull += "#{player}: " + playerFullRolls[player] +" | "
      }

      if @args =~ /details?$/i || @args =~ /full?$/i
        # Show full rolls
        return resultsFull
      else 
        # Just show the final roll
        return results
      end
    end
    
    
  end
end
