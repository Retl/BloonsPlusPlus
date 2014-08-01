#!/usr/bin/env ruby
#
# bones
# by Jonathan Drain
#Lotsa tweaks and stuff done by codepony.
 
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
require_relative 'chargen'
 
module Dicebox # dice functions by JD. http://d20.jonnydigital.com/
 
  class Dice
    def initialize(line)
      @line = line.to_s
      @dice_regex = /((\+|-)?(\d+)(d\d+)?)/
    end
 
    def roll()
      return roll_line(@line)
    end
 
    def roll_line(line)
      line = line.split(";")
      line.each_index do |i|
        if not line[i] =~ @dice_regex
          line.delete_at i
        end
      end
      if not line[0] =~ @dice_regex
        array.delete
      end
      line = line.map {|attack_roll| roll_attack attack_roll.strip}
      return line.join("; ").delete("\001")
    end
 
    def roll_attack(attack)
      attack = attack.split(" ", 2)
      if attack[1] == "" || attack[1] == nil
        comment = attack[0]
      else
        comment = attack[1]
      end
 
      attack[0] =~ /^(\d+)#(.*)/
      if $1
        times = $1.to_i
      else
        times = 1
      end
 
      # Dice cap
      error = false
      if times > 800
        times = 800
        error = true
        comment = comment + ("          " * 10)
      end
 
      if times == 1
        sets = [attack[0]]
      else
        sets = [$2.to_s] * times
      end
 
      sets = sets.map{|roll| roll_roll roll}
      return comment + ": " + sets.join(", ")
    end
 
    def roll_roll(roll)
      rolls = roll.scan(@dice_regex)  # [["1d6", nil, "1", "d6"], ["+1d6", "+", "1", "d6"]]
      originals = rolls.map {|element| element[0].to_s}  # ["1d6", "+1d6", "+1"]
      results = rolls.map {|element| roll_element element}
      # return elements in a coherent roll
      # turn 1d20+2d6-1d6+4-1
      # into 22 [1d20=4; 2d6=1,6; 1d6=-3]
 
      total = 0
      results.flatten.each{|r| total += r}
 
      indiv_results = []
      originals.each_index do |i|
        if originals[i] =~ /d/
          f = originals[i] + "=" + results[i].join(",")
          indiv_results << f
        end
      end
 
      return total.to_s + " [" + indiv_results.join("; ").delete("-").delete("+") + "]"
    end
 
    def roll_element(element)
      # sample ["1d6", nil, "1", "d6"]
      # sample ["+1d6", "+", "1", "d6"]
      # sample ["+1", "+", "1", nil]
      original, sign, numerator, denominator = element[0], element[1], element[2], element[3]
      sign = "+" unless sign
      error = false
 
      # Dice cap
      if numerator.to_i > 800
        numerator = "800"
        original = sign + numerator + denominator # feign original
        error = true
      end
 
      if denominator && denominator.delete("d").to_i > 10000
        denominator = "d10000"
        original = sign + numerator + denominator  # feign original
        error = true
      end
 
      # fix for "d20"
      if (not denominator) and original =~ /^(\+|-)?d(\d+)/
        sign = $1
        numerator = 1
        denominator = $2
      end
 
      if denominator
        result = []
        numerator.to_i.times do
          result << random(denominator.delete("d").to_i)
        end
      else
        result = [numerator.to_i]
      end
 
      # flip result unless sign
      if sign == "-"
        result = result.map{ |r| 0 - r}
      end
 
      # Dice cap
      # invoke "too many dice message" by triggering long line
      if error
        200.times do
          result << 9999
        end
      end
 
      return result
    end
 
    def random(value)
      return 0 if value == 0
      return rand(value)+1
    end
 
  end
end
 
module Bones
  class Client # an "instance" of bones; generally only one
    def initialize(nick, server, port, channels, admin, player_init_bonuses, pass)
      @running = true
 
      @nick = nick
      @server = server # one only
      @port = port
      @channels = channels
      @admin = admin
      @player_init_bonuses = player_init_bonuses
      @pass = pass
 
      connect()
      run()
    end
 
    def connect
      @connection = Connection.new(@server, @port)
 
      if @pass != false
        @connection.speak "PASS #{@pass}"
      end
      @connection.speak "NICK #{@nick}"
      @connection.speak "USER #{@nick} bones * :Bones++ Dicebot: https://github.com/injate/BonesPlusPlus/"
      # This needs some work, faking the client port (54520) right now.
      # http://www.team-clanx.org/articles/socketbot-ident.html
      @connection.speak "IDENT 54520, #{@port} : USERID : UNIX : #{@nick}"
 
      # TODO: fix join bug
      join(@channels)
      sleep 4
      join(@channels)
    end
 
    def join(channels)
      channels.each do |channel|
        # join channel
        @connection.speak "JOIN #{channel}"
        puts "Joining #{channel}"
      end
    end
 
    def leave(channels)
      channels.each do |channel|
        # part channel
        @connection.speak "PART #{channel}"
        @channels.delete(channel)
        puts "Leaving #{channel}"
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
      elsif msg.privmsg && msg.text =~ /^@@@join (#.*)/
        join([$1.to_s])
      elsif msg.privmsg && msg.text =~ /^@@@leave (#.*)/
        leave([$1.to_s])
      elsif msg.privmsg && msg.text =~ /^@@@part (#.*)/
        leave([$1.to_s])
      elsif msg.text =~ /^hay$/i
        reply(msg, "hay :v")
#      elsif msg.privmsg && msg.text =~ /^@@@say (#.*)/
#        reply(msg, $1.to_s)
#        @connection.speak "#{msg.mode} #{msg.origin} :#{msg.name}, #{msg.text}"
      elsif msg.text =~ /^scootaloo$/i
        reply(msg, "20% Cooler")
      elsif msg.text =~ /^gak$/i
        reply(msg, "http://i.imgur.com/eOtxN.png")
      elsif msg.text =~ /^pipshrug$/i
        reply(msg, "http://i.imgur.com/77cFI.png")
#      elsif msg.text =~ /^o\.O$/i
#        reply(msg, [
#          "http://i.imgur.com/Z2Bhq.gif"
#        ].sample)
#      elsif msg.text =~ /^ilushia$/i || msg.text =~ /^ilushia\.$/i
#        reply(msg, [
#          "is soft  http://i.imgur.com/1Pk3z.png",
#          "is soft  http://i.imgur.com/2vJcW.jpg",
#          "is soft  http://i.imgur.com/rUTfX.png"
#        ].sample)
#      elsif msg.text =~ /^fart$/i
#        reply(msg, [
#          "http://i.imgur.com/GYCIA.png",
#          "http://i.imgur.com/sBRJx.png"
#        ].sample)
#      elsif msg.text =~ /^wat$/i || msg.text =~ /^wat\.$/i
#        reply(msg, [
#          "http://i.imgur.com/x5ZdA.gif",
#          "http://i.imgur.com/h6SxP.png",
#          "http://i.imgur.com/cTqAZ.gif",
#          "http://i.imgur.com/31cne.png",
#          "http://i.imgur.com/kXlgT.jpg",
#          "http://i.imgur.com/00Djo.png"
#        ].sample)
      elsif msg.text =~ /^G1$/i || msg.text =~ /^G1\.$/i
        reply(msg, [
          "http://i.imgur.com/ZIOwN.jpg",
          "http://i.imgur.com/CEmcT.jpg",
          "http://i.imgur.com/S68kB.jpg",
          "http://i.imgur.com/NIfds.jpg",
          "http://i.imgur.com/Q5TWg.jpg",
          "http://i.imgur.com/EWZQp.png",
          "http://i.imgur.com/Y5QoS.png",
          "http://i.imgur.com/wf80n.gif",
          "http://i.imgur.com/sAC0J.gif",
          "http://i.imgur.com/NyVQ1.gif",
          "http://i.imgur.com/MMriN.gif",
          "http://i.imgur.com/klMQR.gif",
          "http://i.imgur.com/sIU1b.gif",
          "http://i.imgur.com/cYxsH.gif",
          "http://i.imgur.com/Gfw3c.jpg",
          "http://i.imgur.com/VAbSC.jpg",
          "http://i.imgur.com/VAbSC.jpg",
          "http://i.imgur.com/oepkb.png",
          "http://i.imgur.com/WJYlD.jpg",
          "http://i.imgur.com/kAsQl.jpg",
          "http://i.imgur.com/kAsQl.jpg",
          "http://i.imgur.com/2QhCy.png",
          "http://i.imgur.com/hvSHU.gif",
          "http://i.imgur.com/8cPmi.gif",
          "http://i.imgur.com/NAls7.gif"
        ].sample)
      elsif msg.text =~ /\bbutt bow\b/i || msg.text =~ /\bbutt bows\b/i || msg.text =~ /\bbuttbows\b/i || msg.text =~ /\bbuttbow\b/i
        reply(msg, [
          "http://i.imgur.com/wf80n.gif",
          "http://i.imgur.com/X52Mul.jpg",
          "http://i.imgur.com/1jV7O.gif",
          "http://i.imgur.com/VAbSC.jpg",
          "http://i.imgur.com/2fa2Q.jpg",
          "http://i.imgur.com/54GO2.jpg",
          "http://i.imgur.com/S68kB.jpg"
        ].sample)
      elsif msg.text =~ /^plot$/i || msg.text =~ /^plot\.$/i
        reply(msg, [
          "http://i.imgur.com/yF6b9.gif",
          "http://i.imgur.com/GXEH2.png",
          "http://i.imgur.com/aOvnr.png",
          "http://i.imgur.com/r3jdN.png",
          "http://i.imgur.com/cD0ya.png",
          "http://i.imgur.com/FDuhI.png",
          "http://i.imgur.com/9AJ4d.png",
          "http://i.imgur.com/NlXAf.jpg",
          "http://i.imgur.com/kLRTa.gif",
          "http://i.imgur.com/dcAH5.jpg",
          "http://i.imgur.com/Ewdes.png",
          "http://i.imgur.com/wf80n.gif",
          "http://i.imgur.com/kr2gF.gif",
          "http://i.imgur.com/tB2Ek.png",
          "http://i.imgur.com/lNzUQ.png",
          "http://i.imgur.com/DgoUJ.jpg",
          "http://i.imgur.com/2dkDu.gif",
          "http://i.imgur.com/kbwza.png",
          "http://i.imgur.com/9BKXi.jpg",
          "http://i.imgur.com/1AEhf.png",
          "http://i.imgur.com/92vBl.gif",
          "http://i.imgur.com/9jYVw.gif",
          "http://i.imgur.com/aZfJ3.gif",
          "http://i.imgur.com/k7fVU.jpg",
          "http://i.imgur.com/pm5Cf.jpg",
          "http://i.imgur.com/fShMLl.png",
          "http://i.imgur.com/XjbIDl.png",
          "http://i.imgur.com/TPbSFl.png",
          "http://i.imgur.com/TlxZwl.png",
          "http://i.imgur.com/U1K10.png",
          "http://i.imgur.com/AWz5X.png",
          "http://i.imgur.com/okPRm.png",
          "http://i.imgur.com/okPRm.png",
          "http://i.imgur.com/okPRm.png",
          "http://i.imgur.com/GpW1Vl.png",
          "http://i.imgur.com/ZW4k7.jpg",
          "http://i.imgur.com/AcI8T.gif",
          "http://i.imgur.com/IpUHw.png",
          "http://i.imgur.com/oWat9.jpg",
          "http://i.imgur.com/S1qUq.jpg",
          "http://i.imgur.com/RQsNZ.png"
        ].sample)
      elsif msg.text =~ /^no!/i || msg.text =~ /^no\./i || msg.text =~ /^no\?/i
        reply(msg, [
          "http://i.imgur.com/r6HHS.jpg",
          "http://i.imgur.com/XNFnM.gif",
          "http://i.imgur.com/IdKK4.gif",
          "http://i.imgur.com/BCLHs.gif",
          "http://i.imgur.com/9ti3Y.gif",
          "http://i.imgur.com/nZPFh.gif",
          "http://i.imgur.com/9Nj59.jpg"
        ].sample)
#      elsif msg.text =~ /^wet$/i || msg.text =~ /^wet\.$/i
#        reply(msg, [
#          "http://i.imgur.com/NlXAf.jpg",
#          "http://i.imgur.com/Z6PM2.png",
#          "http://i.imgur.com/hkMO2l.png",
#          "http://i.imgur.com/Zox5x.jpg",
#          "http://i.imgur.com/gNBrsl.png",
#          "http://i.imgur.com/wqKVcl.png",
#          "http://i.imgur.com/yfL4sl.png",
#          "http://i.imgur.com/ciKS7.png",
#          "http://i.imgur.com/UVM3Q.png",
#          "http://i.imgur.com/JH5EM.png",
#          "http://i.imgur.com/41d7w.png",
#          "http://i.imgur.com/8re4o.gif",
#          "http://i.imgur.com/QkvsZl.png",
#          "http://i.imgur.com/yDNAG.png",
#          "http://i.imgur.com/q7gGN.jpg",
#          "http://i.imgur.com/Kgjbt.png",
#          "http://i.imgur.com/ujZQK.jpg",
#          "http://i.imgur.com/uc9Oe.png",
#          "http://i.imgur.com/EAIf2.png"
#        ].sample)
      elsif msg.text =~ /^facebook$/i || msg.text =~ /^facebook\.$/i
        reply(msg, [
          "http://i.imgur.com/QdIIH.png",
          "http://i.imgur.com/CbG9o.png"
        ].sample)
      elsif msg.text =~ /\bfutashy\b/i || msg.text =~ /\bfutashy\.\b/i
        reply(msg, [
          "http://i.imgur.com/TerU5.png",
          "http://i.imgur.com/SMPg7.png",
          "http://i.imgur.com/6LQx7.png",
          "http://i.imgur.com/M3ov4.png",
          "http://i.imgur.com/lgvov.png",
          "http://i.imgur.com/kZFIY.png",
          "http://i.imgur.com/dIuAB.png",
          "http://i.imgur.com/Le28F.png",
          "http://i.imgur.com/c54oZ.png",
          "http://i.imgur.com/Npg9H.png",
          "http://i.imgur.com/11dFB.png",
          "http://i.imgur.com/3A63L.png",
          "http://i.imgur.com/3A63L.png",
          "http://i.imgur.com/3A63L.png"
        ].sample)
      elsif msg.text =~ /\bcrotchboob\b/i || msg.text =~ /\bcrotchboob\.\b/i || msg.text =~ /\bcrotchboobs\b/i || msg.text =~ /\bcrotchboobs\.\b/i
        reply(msg, [
          "http://i.imgur.com/99WjH.gif"
        ].sample)
      elsif msg.text =~ /\bXjuan on fire\b/i
        reply(msg, [
          "http://i.imgur.com/Ii9Dx.png",
          "http://i.imgur.com/RUlzm.png",
          "http://i.imgur.com/3jfes.jpg",
          "http://i.imgur.com/GW1Sf.jpg",
          "http://i.imgur.com/3AISx.png",
          "http://i.imgur.com/0slIC.png",
          "http://i.imgur.com/Zm0Ya.png"
        ].sample)
#      elsif msg.text =~ /^science$/i || msg.text =~ /^science!$/i || msg.text =~ /^science$/i || msg.text =~ /^science\.$/i
#        reply(msg, [
#          "http://i.imgur.com/IQw8q.jpg",
#          "http://i.imgur.com/qIvML.png",
#          "http://i.imgur.com/BUE0n.jpg",
#          "http://i.imgur.com/6PyfV.jpg",
#          "http://i.imgur.com/wKcjA.gif",
#          "http://i.imgur.com/a7DTG.jpg",
#          "http://i.imgur.com/faGtd.png",
#          "http://i.imgur.com/Tgqp2.jpg",
#          "http://i.imgur.com/QsA0T.png"
#        ].sample)
      elsif msg.text =~ /^smooze$/i || msg.text =~ /^smooze\.$/i
        reply(msg, [
          "http://i.imgur.com/4H2x2.png",
          "http://i.imgur.com/R5Pvt.png",
          "http://i.imgur.com/krxCD.jpg",
          "http://i.imgur.com/VYoce.jpg",
          "http://i.imgur.com/R6IdJ.jpg",
          "http://i.imgur.com/HZR9y.png",
          "http://i.imgur.com/pbWwI.png",
          "http://i.imgur.com/BZXoR.jpg",
          "http://i.imgur.com/1ymjr.jpg"
        ].sample)
      elsif msg.text =~ /^rimshot$/i || msg.text =~ /^rimshot\.$/i || msg.text =~ /^rimjob$/i || msg.text =~ /^rimjob\.$/i
        reply(msg, [
          "http://instantrimshot.com/classic/?sound=rimshot&play=true"
        ].sample)
      elsif msg.text =~ /^(augment)/i
        reply(msg, "my vision is augmented. ")
      elsif msg.text =~ /^shipchart$/i
        reply(msg, "https://docs.google.com/spreadsheet/ccc?key=0ApGBpjfNxFNVdHcwdW9DWHg1NkRSSTZSc1o3NXlYOHc#gid=0")
      elsif msg.text =~ /^shiproll$/i
        # Shipping chart
        dice = Dicebox::Dice.new("1d6; 2#1d23+1")
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
	  elsif msg.text == "chargen"
      	for lines in chargen().split("\n")
      		reply(msg, lines)
      	end
      elsif msg.text =~ /^shiproll2$/i
        # Shipping chart
        dice = Dicebox::Dice.new("2#1d6; 2#1d23+1")
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
      elsif msg.text =~ /dam(\d+):(\d+):(\d+)/
        initial_damage = $1.to_i
        damage_threshold = $2.to_i
        damage_resistance = $3.to_i
        dam_taken = (initial_damage-damage_threshold)*(100-damage_resistance) / 100
        reply(msg, "You take " + dam_taken.to_s + " damage.")
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
        when "dance"
          result = "http://i.imgur.com/mqFrH.gif"
        when "what is love"
        when "love"
          result = "http://youtu.be/YsJuNQTZhQk"
        when "okay"
          result = ["http://i.imgur.com/qJGKx.png"].sample
        when "shutup"
          result = ["http://i.imgur.com/qJGKx.png"].sample
        when "rimshot"
          result = "http://instantrimshot.com/classic/?sound=rimshot&play=true"
        when "game"
          result = "http://i.imgur.com/KVsrq.png"
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
      case @args
        when "commands"
          result = "I respond to the following commands.  Tell me '@@@Join #Channelname' to have me join your channel.  I don't respond to any other commands for users below Ultraviolet clearance."
        when "random"
          result = "By the grace of Celestia, I use a modified Mersenne Twister algorithm with a period of 2**19937-1 for a high degree of randomness."
        when "dice"
          result = "Roll dice in the format '1d20+6'.  Multiple sets as so: '2#1d20+6'.  Rolls can be followed with a comment as so:'1d20+6 attack roll'.  Separate multiple rolls with a semicolon, ';'.  "
          result += "I Can add and subtract multiple dice, and I show original rolls when you use a modifier.  "
          result += "Bugs: must specify the '1' in '1d20'.  Also, don't specify a set of 1 (e.g. 1#1d12), it just won't work."
        when "chart"
          result = "VolrathXP built a fun little relationship chart!  To see the chart, say 'shipchart'.  To roll on the chart with roll style one, say 'shiproll'.  Roll style 2, which can provide truly disturbing results, is yours for saying 'shiproll2'."
        when "damage"
          result = "I can provide Fallout style damage calculation, by simplying saying dam<initial damage>:<Damage Threshold>:<Damage Resistance> I will return to you how much damage.  EX: dam:100:10:5 'You take 85 damage'.  I am also very sorry if this results in anypony's death."
        else
          result = "I am Bones, a cybernetic life form. For information on my commands, say 'Bones, Help commands'.  "
          result += "For information on how I make dice rolls, say 'Bones, Help random'.  "
          result += "To learn about dice rolls, say 'Bones, Help dice'.  "
          result += "I have a fun relationship chart! to learn about it, say 'Bones, Help chart'.  "
          result += "I can even calculate the damage done in combat for you, say 'Bones, Help damage'.  "
        #end - not needed, just to help my OCD... I don't like the Ruby language, it makes no sense.
      end
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
 
# I recommend that you change the name of your bot and the channels it joins to avoid
# conflict with other dicebots. Check with your network operator to ensure they allow bots.
 
# NB: As a security measure, some IRC networks prevent IRC bots from joining
# channels too quickly after connecting. Manually encourage it to join with this:
# /msg bones @@@join #channel
 
admin_name = "Retl"
 
your_bot_name = "Bloons"
your_bot_pass = "nickserv_password"
 
server_to_join = "irc.canternet.org"
port = 6667
 
list_of_channels = ["#FalloutEquestria"]
#list_of_channels = ["#xtest", "#xtest2"]
 
player_init_bonuses = {"Fighter" => 2, "Wizard" => 0, "FastRogue" => -3, "SlowRogue" => -1, "Cleric" => 0}
 
# NOTE: To join multiple networks, you can copy this file to create two Boneses.
# Alternatively, if you're familiar with Ruby, it should be straightforward. ('_')b
 
begin
  client = Bones::Client.new(your_bot_name, server_to_join, port, list_of_channels, admin_name, player_init_bonuses, your_bot_pass)
end