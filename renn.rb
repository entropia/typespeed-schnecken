# One-Night-Hack fuer die GPN 3 (http://www.entropia.de/gpn)
require 'sdl'
require 'socket'

class Array
    def shuffle!
        size.downto(2) do |i|
            r = rand(i)
            self[i-1], self[r] = self[r], self[i-1]
        end
        self
    end
end

class Player
    attr_reader :score
    attr_reader :idx
    attr_reader :dazed
    attr_reader :pos

    def initialize(game, sock)
        @game = game
        @sock = sock
        @score= 0
        @pos  = -200
        @idx  = 0
        @name = nil
        @dazed= false
        
        @thread = Thread.new do 
            sleep 0.2
            runner
        end
        # @thread.abort_on_exception=true
    end

    def name
        @name || "<unbenannt>"
    end

    def ready?
        not @name.nil?
    end

    def write(what = "")
        begin
            @sock.syswrite what + "\r\n"
        rescue => e
            p e
        end
    end

    def read
        @sock.sysread(100)
    end

    def runner
        write "Willkommen auf Rennschnecken-Typespeed Version 0.1"
        write "--------------------------------------------------"
        write "Nach dem Start des Rennens sind die angezeigten Wörter"
        write "abzutippen. Je schneller das Wort abgetippt wird, desto"
        write "weiter bewegt sich die Schnecke vorwärts. Bei fehlerhaften"
        write "Eingaben bewegt sich die Schnecke rückwärts."
        write
        write "Wörter: " + @game.worddescription 
        write
        write "Nickname?"
        @name = read.strip
        @game.players.each do |p|
            next if p == self
            next unless p.ready?
            p.write "Neuer Spieler #@name"
        end
        write "Warte auf weitere Spieler (%d insgesamt)" % @game.maxplayer
        Thread.stop
        loop do 
            word = @game.getWord(@idx)
            write word
            a = Time.now
            reply = read
            b = Time.now
            correct = reply.strip == word
            points = calcscore(b - a, correct, word, @idx)
            rank = @game.players.inject(1) { |mem, cur| cur.score > @score ? mem + 1 : mem }
            write "%s: Score: %d -> %d/%d, Rank: %d/%d" % 
                  [correct ? "OK" : "NO", points, @score, 300, rank, @game.maxplayer]
            @idx += 1
        end
    end

    def calcscore(time, correct, word, idx)
        # p time, correct, idx
        timePerChar = time / word.size
        points = correct ? 4 / timePerChar : -10
        @dazed = points < 0
        @score += points
        if @score > 300
            @game.finalmsg = "Spieler #@name hat gewonnen"
            Thread.main.wakeup 
            sleep
        end
        points
    end

    def kill
        @thread.kill
    end

    def disconnect
        @sock.close
    end

    def go
        @thread.wakeup
    end

    def move
        case
        when @pos < @score 
            @pos += (@score - @pos) / 10
        when @pos > @score 
            @pos -= (@pos - @score) / 4;
        end
    end
end

class Game
    attr_writer :finalmsg
    attr_reader :maxplayer
    attr_reader :players

    attr_reader :worddescription 

    def initialize(wordlist, maxplayer, info)
        @players   = []
        @maxplayer = maxplayer
        @finalmsg  = ""
        @incom     = TCPServer.open(0, 1234)
        @info      = info
        @wordlist  = wordlist
        @state     = :pregame
    end

    def kick(pnr)
        return unless @players.size > pnr
        @players[pnr].disconnect
        @players[pnr].kill
        @players.delete_at(pnr)
    end

    def startGuiThread
        @gui = Thread.new do
            sleep 0.2
            
            SDL.init(SDL::INIT_VIDEO)
            screen = SDL::setVideoMode(640,480,16,SDL::HWSURFACE) # | SDL::FULLSCREEN)
            SDL::WM::setCaption('Typespeed','typespeed')
            SDL::Mouse::hide

            SDL::TTF.init
            font = SDL::TTF.open('nihongo.ttf',24)
            font.style = SDL::TTF::STYLE_NORMAL

            schnecke = []
            0.upto 0 do |i| # hier erhoehen fuer mehr schnecken
                image = SDL::Surface.loadBMP("schnecke%d.bmp" % i)
                image.setColorKey(SDL::SRCCOLORKEY,0)
                schnecke[i] = image.displayFormat
            end

            image = SDL::Surface.loadBMP("wiese.bmp")
            image.setColorKey(SDL::SRCCOLORKEY,0)
            back = image.displayFormat
            
            loop do 
                while event = SDL::Event2.poll
                    case event
                    when SDL::Event2::Quit
                        exit
                    when SDL::Event2::KeyDown
                        case event.sym
                        when SDL::Key::SPACE
                            screen.toggleFullScreen
                        when SDL::Key::ESCAPE
                            exit
                        when SDL::Key::UP:
                            @maxplayer -= 1
                        when SDL::Key::DOWN
                            @maxplayer += 1
                        when SDL::Key::K1: kick(0) 
                        when SDL::Key::K2: kick(1) 
                        when SDL::Key::K3: kick(2) 
                        when SDL::Key::K4: kick(3) 
                        when SDL::Key::K5: kick(4) 
                        when SDL::Key::K6: kick(5) 
                        end
                    end
                end

                SDL.blitSurface(back,0,0,640,480,screen,0,0)

                # Bla
                case @state
                when :pregame
                    font.drawSolidUTF8(screen,@info,180,70,255,255,255)
                    font.drawSolidUTF8(screen,"Jetzt verbinden!",230,180,255,255,255)
                    font.drawSolidUTF8(screen,@worddescription,220,210,255,255,255)
                when :countdown
                    font.drawSolidUTF8(screen,"Noch #@countdown Sekunden!",230,180,255,255,255)
                when :finished
                    font.drawSolidUTF8(screen,@finalmsg,180,70,255,255,255)
                end
                
                # Raster
                screen.fillRect(490, 250, 2, @maxplayer * 40, 0);
                0.upto(@maxplayer) do |i|
                    screen.fillRect(0, i * 40 + 250, 640, 2, 0);
                end

                # Schnecken
                @players.each_with_index do |p,i|
                    p.move

                    SDL.blitSurface(schnecke[i % schnecke.size],0,0,197,181,screen, p.pos,i * 40 + 100)

                    if @state == :running
                        font.drawSolidUTF8(screen,getWord(p.idx),p.pos + 20,i * 40 + 255,0,0,0)
                    end
                    font.drawSolidUTF8(screen,p.name,495,i * 40 + 255,255,255,255)
                end

                # screen.updateRect(0,0,0,0)
                screen.flip
                sleep 0.05
            end
        end
        @gui.abort_on_exception=true
    end

    def start
        @words = File.open(@wordlist).inject([]) { |mem,cur| mem << cur.strip }
        @worddescription = @words.shift
        @words.shuffle!

        startGuiThread

        # Auf Spieler warten
        while @players.size < @maxplayer
            @players << Player.new(self, @incom.accept)
        end
        @incom.close
        
        until @players.inject(true) { |mem,cur| mem & cur.ready? }
            sleep 0.5
        end

        liste = @players.map{ |p| p.name }.join(", ")
        @players.each do |p|
            p.write "Spieler: " + liste
        end

        @state = :countdown

        5.downto 1 do |sek|
            @countdown = sek
            @players.each do |p|
                p.write "Start in %d Sekunden!" % sek
            end
            sleep 1
        end

        @players.each do |p|
            p.go
        end

        @state = :running

        @timeout = Thread.new do 
            sleep 120
            @finalmsg = "Zeit vorbei"
            Thread.main.wakeup
            sleep
        end

        # Warten bis Spiel zu Ende
        Thread.stop

        @state = :finished

        @timeout.kill

        puts @finalmsg

        rank = @players.sort_by{|p| -p.score}.map{|p| p.name + " " + p.score.to_i.to_s}.join(", ")

        @players.each do |p|
            p.write rank
            p.write 
            p.write @finalmsg
            p.kill
        end

        sleep 2 

        @players.each do |p|
            p.disconnect
        end

        sleep 8
    end

    def getWord(idx)
        @words[idx % @words.size]
    end
end

unless ARGV.size == 3
    puts "renn.rb <wordfile> <players> <infotext>"
    exit 1
end

Game.new(ARGV[0], ARGV[1].to_i, ARGV[2]).start
