require 'dl'
require_relative 'RbTSCP-Consts'

#/*
# *	MAIN.C
# *	Tom Kerrigan's Simple Chess Program (TSCP)
# *
# *	Copyright 1997 Tom Kerrigan
# */
#
# Conversão: Gabriel "Gab!" Teles

# Patch 1A : Correção da profundidade que não estava sendo atualizada
# Patch 1B : Correção da ordem de checagem dos empates
# Patch 1C : Correção no tratamento de movimentos (movimentos incompletos geravam
#            erro que forçava a finalização)

class TSCP
  include TSCPConsts
  
  def initialize
    @color  = Array.new(64, 0)  # LIGHT, DARK, or EMPTY
    @piece  = Array.new(64, 0)  # PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING, or EMPTY
    @side   = 0                 # The side to move
    @xside  = 0                 # the side not to move
    @castle = 0                 # A bitfield with the castle permissions. if 1 
                                # is set, white can still castle kingside. 2 is 
                                # white queenside. 4 is black kingside. 8 is 
                                # black queenside.
    @ep     = 0                 # The en passant square. if white moves e2e4, 
                                # the en passant square is set to e3, because 
                                # that's where a pawn would move in an en 
                                # passant capture
    @fifty  = 0                 # The number of moves since a capture or pawn 
                                # move, used to handle the fifty-move-draw rule
    @hash   = 0                 # A (more or less) unique number that 
                                # corresponds to the position
    @ply    = 0                 # The number of half-moves (ply) since the root 
                                # of the search tree
    @hply   = 0                 # h for history; the number of ply since the 
                                # beginning of the game
    
    # gen_dat is some memory for move lists that are created by the move
    # generators. The move list for ply n starts at first_move[n] and ends
    # at first_move[n + 1].
    @gen_dat = Array.new(GEN_STACK){Gen_t.new}
    @first_move = Array.new(MAX_PLY, 0)

    # the history heuristic array (used for move ordering)
    @history = Array.new(64){Array.new(64, 0)}

    # we need an array of hist_t's so we can take back the moves we make
    @hist_dat = Array.new(HIST_STACK){Hist_t.new}

    # the engine will search for max_time milliseconds or until it finishes
    # searching max_depth ply.
    @max_time = 0
    @max_depth = 0

    # the time when the engine starts searching, and when it should stop
    @start_time = 0
    @stop_time  = 0

    @nodes = 0 # the number of nodes we've searched */

    # a "triangular" PV array; for a good explanation of why a triangular
    # array is needed, see "How Computers Play Chess" by Levy and Newborn.
    @pv = Array.new(MAX_PLY){Array.new(MAX_PLY){Move.new}}
    @pv_length = Array.new(MAX_PLY, 0)
    @follow_pv = false

    # random numbers used to compute hash; see set_hash() in board.c 
    @hash_piece = Array.new(2){Array.new(6){Array.new(64, 0)}}# indexed by piece [color][type][square]
    @hash_side = 0
    @hash_ep = Array.new(64, 0);
    
    # the opening book file
    @book_file = nil
    
    # ???
    @stop_search = false
    
    # pawn_rank[x][y] is the rank of the least advanced pawn of color x on file
    #   y - 1. There are "buffer files" on the left and right to avoid special-case
    #   logic later. If there's no pawn on a rank, we pretend the pawn is
    #   impossibly far advanced (0 for LIGHT and 7 for DARK). This makes it easy to
    #   test for pawns on a rank and it simplifies some pawn evaluation code. */
    @pawn_rank = Array.new(2){Array.new(10, 0)}
    @piece_mat = Array.new(2, 0);  # the value of a side's pieces */
    @pawn_mat  = Array.new(2, 0);  # the value of a side's pawns */
    
    
    init_hash();
    init_board();
    open_book();
    gen();
    @computer_side = EMPTY;
    @max_time = 1 << 25;
    @max_depth = 4;
  end
  
  
  # open_book() opens the opening book file and initializes the random number
  # generator so we play random book moves.

  def open_book
    srand(Time.now.to_i);
    #book_file = fopen("book.txt", "r");
    @book_file = File.open('book.txt', 'r')
	end


  # close_book() closes the book file. This is called when the program exits.
  def close_book
    @book_file.close if (@book_file)
		@book_file = nil
  end


  # book_move() returns a book move (in integer format) or -1 if there is no
  # book move.

  def book_move
    move = Array.new(50, 0)
    count = Array.new(50, 0)
    moves = 0
    total_count = 0
    
    return -1 if (!@book_file || @hply > 25)

    # /* line is a string with the current line, e.g., "e2e4 e7e5 g1f3 " */
    #  line[0] = '\0';
    line = ""
    @hply.times{|i|
      line << sprintf("%s ", move_str(@hist_dat[i].m.b))
    }

    # compare line to each line in the opening book 
    #fseek(book_file, 0, SEEK_SET);
    @book_file.seek(0)
    
    while (book_line = @book_file.gets)
      if (book_match(line, book_line))
        # /* parse the book move that continues the line */
        m = parse_move(book_line[line.size..-1]);
        next if (m == -1)
        m = gen_dat[m].m.u;

        #/* add the book move to the move list, or update the move's
        #   count */
        k = 0
        moves.times{|j|
          if (move[j] == m)
            count[j] += 1
            break;
          end
          k += 1
        }
        
        if (k == moves)
          move[moves] = m
          count[moves] = 1
          moves += 1
        end
        
        total_count += 1
      end
    end

    # /* no book moves? */
    return -1 if (moves == 0)

    #/* Think of total_count as the set of matching book lines.
    #   Randomly pick one of those lines (j) and figure out which
    #   move j "corresponds" to. */
    j = rand(RAND_MAX) % total_count;
    moves.times{|i|
      j -= count[i];
      return move[i] if (j <= 0)
    }
    
    return -1;  # /* shouldn't get here */
  end


  # book_match() returns TRUE if the first part of s2 matches s1.

  def book_match(s1, s2)
    return false if s1.size > s2.size
    return s2[0, s1.size] == s1
    
    i = 0
    while i < s1.size
      return false if (s2[i] == nil || s2[i] != s1[i])
      i += 1
    end
    return true
  end

  
  # init_board() sets the board to the initial game state.
  def init_board()
    64.times{|i|
      @color[i] = INIT_COLOR[i]
      @piece[i] = INIT_PIECE[i]
    }
    @side = LIGHT
    @xside = DARK
    @castle = 15
    @ep = -1
    @fifty = 0
    @ply = 0
    @hply = 0
    set_hash();  # /* init_hash() must be called before this function */
    @first_move[0] = 0
  end


  # init_hash() initializes the random numbers used by set_hash().
  def init_hash
    srand(0)
    
    2.times{|i| 6.times{|j| 64.times{|k|
      @hash_piece[i][j][k] = hash_rand()
    }}}
    
    @hash_side = hash_rand()
    
    64.times{|i|
      @hash_ep[i] = hash_rand()
    }
  end


  # hash_rand() XORs some shifted random numbers together to make sure
  # we have good coverage of all 32 bits. (rand() returns 16-bit numbers
  # on some systems.)

  def hash_rand
    r = 0

    32.times{|i|
      r ^= rand(RAND_MAX) << i
    }
    
    return r
  end


=begin
    set_hash() uses the Zobrist method of generating a unique number (hash)
    for the current chess position. Of course, there are many more chess
    positions than there are 32 bit numbers, so the numbers generated are
    not really unique, but they're unique enough for our purposes (to detect
    repetitions of the position). 
    The way it works is to XOR random numbers that correspond to features of
    the position, e.g., if there's a black knight on B8, hash is XORed with
    hash_piece[BLACK][KNIGHT][B8]. All of the pieces are XORed together,
    hash_side is XORed if it's black's move, and the en passant square is
    XORed if there is one. (A chess technicality is that one position can't
    be a repetition of another if the en passant state is different.)
=end

  def set_hash()
    @hash = 0
    64.times{|i|
      if (@color[i] != EMPTY)
        @hash ^= @hash_piece[@color[i]][@piece[i]][i];
      end
    }
    
    @hash ^= @hash_side if (@side == DARK)
    @hash ^= @hash_ep[@ep] if (@ep != -1)
  end


  # in_check() returns TRUE if side s is in check and FALSE
  # otherwise. It just scans the board to find side s's king
  # and calls attack() to see if it's being attacked. */
  def in_check(s)
    64.times{|i|
      if (@piece[i] == KING && @color[i] == s)
        return attack(i, s ^ 1)
      end
    }
    return true  # shouldn't get here
  end


  # attack() returns TRUE if square sq is being attacked by side
  # s and FALSE otherwise.
  def attack(sq, s)
    64.times{|i|
      if (@color[i] == s)
        if (@piece[i] == PAWN)
          if (s == LIGHT)
            return true if (COL(i) != 0 && i - 9 == sq)
            return true if (COL(i) != 7 && i - 7 == sq)
          else
            return true if (COL(i) != 0 && i + 7 == sq)
            return true if (COL(i) != 7 && i + 9 == sq)
          end
        else
          OFFSETS[@piece[i]].times{|j|
            n = i
            loop do
              n = MAILBOX[MAILBOX64[n] + OFFSET[@piece[i]][j]];
              break if (n == -1)
              return true if (n == sq)
              break if (@color[n] != EMPTY)
              break if (!SLIDE[@piece[i]])
            end
          }
        end
      end
    }
    return false
  end


=begin
   gen() generates pseudo-legal moves for the current position.
   It scans the board to find friendly pieces and then determines
   what squares they attack. When it finds a piece/square
   combination, it calls gen_push to put the move on the "move
   stack."
=end

  def gen
    # so far, we have no moves for the current ply 
    @first_move[@ply + 1] = @first_move[@ply];

    64.times{|i|
      if (@color[i] == @side)
        if (@piece[i] == PAWN)
          if (@side == LIGHT)
            gen_push(i, i - 9, 17) if (COL(i) != 0 && @color[i - 9] == DARK)
            gen_push(i, i - 7, 17) if (COL(i) != 7 && @color[i - 7] == DARK)
            if (@color[i - 8] == EMPTY)
              gen_push(i, i -  8, 16)
              gen_push(i, i - 16, 24) if (i >= 48 && @color[i - 16] == EMPTY)
            end
          else
            gen_push(i, i + 7, 17) if (COL(i) != 0 && @color[i + 7] == LIGHT)
            gen_push(i, i + 9, 17) if (COL(i) != 7 && @color[i + 9] == LIGHT)
            if (@color[i + 8] == EMPTY)
              gen_push(i, i +  8, 16)
              gen_push(i, i + 16, 24) if (i <= 15 && @color[i + 16] == EMPTY)
            end
          end
        else
          OFFSETS[@piece[i]].times{|j|
            n = i
            loop do
              n = MAILBOX[MAILBOX64[n] + OFFSET[@piece[i]][j]];
              break if (n == -1)
              if (@color[n] != EMPTY)
                gen_push(i, n, 1) if (@color[n] == @xside)
                break
              end
              gen_push(i, n, 0);
              break if (!SLIDE[@piece[i]])
            end
          }
        end
      end
    }

    # generate castle moves
    if (@side == LIGHT)
      gen_push(E1, G1, 2) if CCOND(@castle & 1)
      gen_push(E1, C1, 2) if CCOND(@castle & 2)
    else
      gen_push(E8, G8, 2) if CCOND(@castle & 4)
      gen_push(E8, C8, 2) if CCOND(@castle & 8)
    end
	
    # generate en passant moves
    if (@ep != -1)
      if (@side == LIGHT)
        if (COL(@ep) != 0 && @color[@ep + 7] == LIGHT && @piece[@ep + 7] == PAWN)
          gen_push(@ep + 7, @ep, 21);
        end
        
        if (COL(@ep) != 7 && @color[@ep + 9] == LIGHT && @piece[@ep + 9] == PAWN)
          gen_push(@ep + 9, @ep, 21);
        end
      else
        if (COL(@ep) != 0 && @color[@ep - 9] == DARK && @piece[@ep - 9] == PAWN)
          gen_push(@ep - 9, @ep, 21)
        end
        
        if (COL(@ep) != 7 && @color[@ep - 7] == DARK && @piece[@ep - 7] == PAWN)
          gen_push(@ep - 7, @ep, 21)
        end
      end
    end
  end

=begin
   gen_caps() is basically a copy of gen() that's modified to
   only generate capture and promote moves. It's used by the
   quiescence search. */
=end
  def gen_caps
    @first_move[@ply + 1] = @first_move[@ply];
	
    64.times{|i|
      if (@color[i] == @side)
        if (@piece[i]==PAWN)
          if (@side == LIGHT)
            gen_push(i, i - 9, 17) if (COL(i) != 0 && @color[i - 9] == DARK)
            gen_push(i, i - 7, 17) if (COL(i) != 7 && @color[i - 7] == DARK)
            gen_push(i, i - 8, 16) if (i <= 15 && @color[i - 8] == EMPTY)
          end
            
          if (@side == DARK)
            gen_push(i, i + 7, 17) if (COL(i) != 0 && @color[i + 7] == LIGHT)
            gen_push(i, i + 9, 17) if (COL(i) != 7 && @color[i + 9] == LIGHT)
            gen_push(i, i + 8, 16) if (i >= 48 && @color[i + 8] == EMPTY)
          end
        else
          OFFSETS[@piece[i]].times{|j|
            n = i
            loop do
              n = MAILBOX[MAILBOX64[n] + OFFSET[@piece[i]][j]];
              break if (n == -1)
              if (@color[n] != EMPTY)
                gen_push(i, n, 1) if (@color[n] == @xside)
                break
              end
              break if (!SLIDE[@piece[i]])
            end
          }
        end
      end
    }
    
    if (@ep != -1)
      if (@side == LIGHT)
        if (COL(@ep) != 0 && @color[@ep + 7] == LIGHT && @piece[@ep + 7] == PAWN)
          gen_push(@ep + 7, @ep, 21);
        end
        
        if (COL(@ep) != 7 && @color[@ep + 9] == LIGHT && @piece[@ep + 9] == PAWN)
          gen_push(@ep + 9, @ep, 21);
        end
      else
        if (COL(@ep) != 0 && @color[@ep - 9] == DARK && @piece[@ep - 9] == PAWN)
          gen_push(@ep - 9, @ep, 21);
        end
        
        if (COL(@ep) != 7 && @color[@ep - 7] == DARK && @piece[@ep - 7] == PAWN)
          gen_push(@ep - 7, @ep, 21);
        end
      end
    end
  end

=begin
   gen_push() puts a move on the move stack, unless it's a
   pawn promotion that needs to be handled by gen_promote().
   It also assigns a score to the move for alpha-beta move
   ordering. If the move is a capture, it uses MVV/LVA
   (Most Valuable Victim/Least Valuable Attacker). Otherwise,
   it uses the move's history heuristic value. Note that
   1,000,000 is added to a capture move's score, so it
   always gets ordered above a "normal" move. 
=end

  def gen_push(from, to, bits)
    if CCOND(bits & 16)
      if (@side == LIGHT)
        if (to <= H8)
          gen_promote(from, to, bits)
          return
        end
      else
        if (to >= A1)
          gen_promote(from, to, bits)
          return
        end
      end
    end
    
    g = @gen_dat[@first_move[@ply + 1]]
    @first_move[@ply + 1] += 1
    g.m.b.from    = from
    g.m.b.to      = to
    g.m.b.promote = 0
    g.m.b.bits    = bits
    
    if (@color[to] != EMPTY)
      g.score = 1000000 + (@piece[to] * 10) - @piece[from]
    else
      g.score = @history[from][to]
    end
  end


=begin 
  gen_promote() is just like gen_push(), only it puts 4 moves
  on the move stack, one for each possible promotion piece
=end

  def gen_promote(from, to, bits) 
    i = KNIGHT
    while i < QUEEN
      g = @gen_dat[@first_move[@ply + 1]]
      @first_move[@ply + 1] += 1
      g.m.b.from    = from
      g.m.b.to      = to
      g.m.b.promote = i
      g.m.b.bits    = (bits | 32)
      g.score       = 1000000 + (i * 10)
      i += 1
    end
  end

=begin
  makemove() makes a move. If the move is illegal, it
  undoes whatever it did and returns FALSE. Otherwise, it
  returns TRUE.
=end

  def makemove(m)
    # test to see if a castle move is legal and move the rook
    # (the king is moved with the usual move code later) */
    if CCOND(m.bits & 2)
      return false if in_check(side)
      
      case (m.to)
        when 62
          if (@color[F1] != EMPTY || @color[G1] != EMPTY ||
              attack(F1, @xside) || attack(G1, @xside))
            return false
          end
          
          from = H1;
          to = F1;
        when 58
          if (@color[B1] != EMPTY || @color[C1] != EMPTY || @color[D1] != EMPTY ||
              attack(C1, @xside) || attack(D1, @xside))
            return false
          end
          
          from = A1
          to = D1
        when 6
          if (@color[F8] != EMPTY || @color[G8] != EMPTY ||
              attack(F8, @xside) || attack(G8, @xside))
            return false
          end
          from = H8
          to = F8
        when 2
          if (@color[B8] != EMPTY || @color[C8] != EMPTY || @color[D8] != EMPTY ||
              attack(C8, @xside) || attack(D8, @xside))
            return false
          end
          from = A8;
          to = D8;
        else # shouldn't get here 
          from = -1;
          to = -1;
      end
        
      @color[to] = @color[from];
      @piece[to] = @piece[from];
      @color[from] = EMPTY;
      @piece[from] = EMPTY;
    end

    # back up information so we can take the move back later. */
    @hist_dat[@hply].m.b     = m
    @hist_dat[@hply].capture = @piece[m.to]
    @hist_dat[@hply].castle  = @castle
    @hist_dat[@hply].ep      = @ep
    @hist_dat[@hply].fifty   = @fifty
    @hist_dat[@hply].hash    = @hash
    @ply += 1
    @hply += 1

    # update the castle, en passant, and
    # fifty-move-draw variables
    @castle &= CASTLE_MASK[m.from] & CASTLE_MASK[m.to]
    if CCOND(m.bits & 8)
      if (@side == LIGHT)
        @ep = m.to + 8;
      else
        @ep = m.to - 8;
      end
    else
      @ep = -1
    end
    
    if CCOND(m.bits & 17)
      @fifty = 0
    else
      @fifty += 1
    end

    # move the piece
    @color[m.to] = side
    if CCOND(m.bits & 32)
      @piece[m.to] = m.promote;
    else
      @piece[m.to] = @piece[m.from];
    end
    
    @color[m.from] = EMPTY;
    @piece[m.from] = EMPTY;

    # erase the pawn if this is an en passant move */
    if CCOND(m.bits & 4)
      if (side == LIGHT)
        @color[m.to + 8] = EMPTY;
        @piece[m.to + 8] = EMPTY;
      else
        @color[m.to - 8] = EMPTY;
        @piece[m.to - 8] = EMPTY;
      end
    end

    # switch sides and test for legality (if we can capture
    #   the other guy's king, it's an illegal position and
    #   we need to take the move back)
    @side ^= 1
    @xside ^= 1
    if (in_check(@xside))
      takeback()
      return false
    end
    set_hash()
    return true
  end


  # takeback() is very similar to makemove(), only backwards :)

  def takeback
    @side ^= 1
    @xside ^= 1
    
    @ply -= 1
    @hply -= 1
    
    m = @hist_dat[@hply].m.b
    @castle = @hist_dat[@hply].castle
    @ep = @hist_dat[@hply].ep
    @fifty = @hist_dat[@hply].fifty
    @hash = @hist_dat[@hply].hash
    @color[m.from] = @side
	
    if CCOND(m.bits & 32)
      @piece[m.from] = PAWN;
    else
      @piece[m.from] = @piece[m.to];
    end
    
    if (@hist_dat[@hply].capture == EMPTY)
      @color[m.to] = EMPTY;
      @piece[m.to] = EMPTY;
    else 
      @color[m.to] = @xside;
      @piece[m.to] = @hist_dat[@hply].capture;
    end
  
    if CCOND(m.bits & 2)
      case (m.to)
        when 62
          from = F1
          to = H1
        when 58
          from = D1
          to = A1
        when 6
          from = F8
          to = H8
        when 2
          from = D8
          to = A8
        else # shouldn't get here
          from = -1
          to = -1
      end
      
      @color[to] = @side;
      @piece[to] = ROOK;
      @color[from] = EMPTY;
      @piece[from] = EMPTY;
    end
    
    if CCOND(m.bits & 4)
      if (@side == LIGHT)
        @color[m.to + 8] = @xside
        @piece[m.to + 8] = PAWN
      else
        @color[m.to - 8] = @xside
        @piece[m.to - 8] = PAWN
      end
    end
  end


=begin
   think() calls search() iteratively. Search statistics
   are printed depending on the value of output:
   0 = no output
   1 = normal output
   2 = xboard format output
=end

  def think(output)
    # /* try the opening book first */
    k = book_move
    if (k != -1)
      @pv[0][0].u = k
      return 
    end
    
    # some code that lets us longjmp back here and return
    #  from think() when our time is up
    @stop_search = true
    # setjmp(env);
    #if (stop_search)
    #  /* make sure to take back the line we were searching */
    #  takeback while CCOND(@ply)
    #  return
    #end

    @start_time = get_ms();
    @stop_time = @start_time + @max_time;

    @ply = 0
    @nodes = 0

    #memset(pv, 0, sizeof(pv));
    @pv.each{|ary| ary.each{|mov| mov.u = 0 }}
    #memset(history, 0, sizeof(history));
    @history.each{|ary| ary.map!{ 0 }}
    
    printf("ply      nodes  nodes/sec  score  pv\n") if (output == 1)
    @start = get_ms()
    @lastNodes = 0
    Thread.new{
      i = 1
      while (i <= @max_depth)
        @follow_pv = true
        
        x = search(-10000, 10000, i);
        
        if (output == 1)
          at = get_ms()
          nodesSec = (1000 * (@nodes - @lastNodes)) / (at - @start).to_f
          @start = at
          @lastNodes = @nodes
          printf("%3d  %9d  %4.4f  %5d ", i, @nodes, nodesSec, x);
        elsif (output == 2)
          printf("%d %d %d %d", i, x, (get_ms() - @start_time) / 10, @nodes);
        end
        
        if CCOND(output)
          @pv_length[0].times{|j|
            printf(" %s", move_str(@pv[0][j].b));
          }
          printf("\n");
          
          #fflush(stdout);
          $stdout.flush
        end
        
        break if (x > 9000 || x < -9000)
        i += 1
      end
      
      @stop_search = false
    }.join(@max_time/1000.0) # milli -> sec
    
    if (@stop_search)
      # /* make sure to take back the line we were searching */
      takeback while CCOND(@ply)
    end
  end


  # search() does just that, in negamax fashion
  def search(alpha, beta, depth)
    # int i, j, x;
    # BOOL c, f;
    
    #/* we're as deep as we want to be; call quiesce() to get
    #   a reasonable score and return it. */
    if !CCOND(depth)
      return quiesce(alpha, beta);
    end
    @nodes += 1

    # do some housekeeping every 1024 nodes 
    # checkup if ((@nodes & 1023) == 0)
    
    @pv_length[@ply] = @ply;

    #/* if this isn't the root of the search tree (where we have
    #   to pick a move and can't simply return 0) then check to
    #   see if the position is a repeat. if so, we can assume that
    #   this line is a draw and return 0. */
    return 0 if CCOND(@ply) && CCOND(reps())
      
    # are we too deep? 
    return eval() if (@ply >= MAX_PLY - 1)
    return eval() if (@hply >= HIST_STACK - 1)

    # are we in check? if so, we want to search deeper
    c = in_check(side);
    depth += 1 if (c)
    gen()
    
    sort_pv if (@follow_pv)  # are we following the PV? 
    f = false;

    # loop through the moves
    i = @first_move[@ply] 
    while (i < @first_move[@ply + 1])
      sort(i);
      if (!makemove(@gen_dat[i].m.b))
        i += 1
        next
      end
      
      f = true;
      x = -search(-beta, -alpha, depth - 1)
      takeback()
      
      if (x > alpha)

        #/* this move caused a cutoff, so increase the history
        #   value so it gets ordered high next time we can
        #   search it */
        @history[@gen_dat[i].m.b.from][@gen_dat[i].m.b.to] += depth;
        return beta if (x >= beta)
        alpha = x;

        # update the PV 
        @pv[@ply][@ply] = @gen_dat[i].m;
        j = @ply + 1
        while (j < @pv_length[@ply + 1])
          @pv[@ply][j] = @pv[@ply + 1][j];
          j += 1
        end
        @pv_length[@ply] = @pv_length[@ply + 1];
      end
      
      i += 1
    end

    # no legal moves? then we're in checkmate or stalemate */
    if (!f)
      if (c)
        return -10000 + ply
      else
        return 0
      end
    end

    # /* fifty move draw rule */
    return 0 if (@fifty >= 100)
    return alpha;
  end

=begin
   quiesce() is a recursive minimax search function with
   alpha-beta cutoffs. In other words, negamax. It basically
   only searches capture sequences and allows the evaluation
   function to cut the search off (and set alpha). The idea
   is to find a position where there isn't a lot going on
   so the static evaluation function will work.
=end

  def quiesce(alpha, beta)
    #int i, j, x;

    @nodes += 1
    
    # do some housekeeping every 1024 nodes 
    # checkup() if ((@nodes & 1023) == 0)
    
    @pv_length[@ply] = @ply;

    #  are we too deep? 
    return eval() if (@ply >= MAX_PLY - 1)
    return eval() if (@hply >= HIST_STACK - 1)

    # /* check with the evaluation function */
    x = eval();
    return beta if (x >= beta)
    alpha = x if (x > alpha)

    gen_caps();
    sort_pv() if (@follow_pv) # /* are we following the PV? */

    # /* loop through the moves */
    i = @first_move[@ply]
    while (i < @first_move[@ply + 1])
      sort(i);
      if (!makemove(gen_dat[i].m.b))
        i += 1
        next 
      end
      
      x = -quiesce(-beta, -alpha);
      takeback();
      
      if (x > alpha)
        return beta if (x >= beta)
        alpha = x;

        # /* update the PV */
        @pv[@ply][@ply] = @gen_dat[i].m;
        j = @ply + 1
        while (j < @pv_length[@ply + 1])
          @pv[@ply][j] = @pv[@ply + 1][j];
          j += 1
        end
        
        @pv_length[@ply] = @pv_length[@ply + 1];
      end
      
      i += 1
    end
    
    return alpha
  end

=begin
   reps() returns the number of times the current position
   has been repeated. It compares the current value of hash
   to previous values.
=end

  def reps
    r = 0
    
    i = @hply - @fifty
    while (i < @hply)
      r += 1 if (@hist_dat[i].hash == hash)
      i += 1
    end
    
    return r;
  end

=begin
   sort_pv() is called when the search function is following
   the PV (Principal Variation). It looks through the current
   ply's move list to see if the PV move is there. If so,
   it adds 10,000,000 to the move's score so it's played first
   by the search function. If not, follow_pv remains FALSE and
   search() stops calling sort_pv().
=end

  def sort_pv()
    @follow_pv = false
    i = @first_move[@ply]
    while (i < @first_move[@ply + 1])
      if (@gen_dat[i].m.u == @pv[0][@ply].u)
        @follow_pv = true
        @gen_dat[i].score += 10000000
        return
      end
      i += 1
    end
  end


=begin
   sort() searches the current ply's move list from 'from'
   to the end to find the move with the highest score. Then it
   swaps that move and the 'from' move so the move with the
   highest score gets searched next, and hopefully produces
   a cutoff. */
=end
  def sort(from)
    #int i;
    #int bs;  /* best score */
    #int bi;  /* best i */
    #gen_t g;

    bs = -1
    bi = from
    
    i = from
    while (i < @first_move[@ply + 1])
      if (gen_dat[i].score > bs)
        bs = @gen_dat[i].score;
        bi = i;
      end
      i += 1
    end
    
    g = @gen_dat[from];
    @gen_dat[from] = @gen_dat[bi];
    @gen_dat[bi] = g;
  end

  def eval() 
    #int i;
    #int f;  /* file */
    #int score[2];  /* each side's score */
    score = Array.new(2, 0)

    # this is the first pass: set up pawn_rank, piece_mat, and pawn_mat. */
    10.times{|i|
      @pawn_rank[LIGHT][i] = 0;
      @pawn_rank[DARK][i] = 7;
    }
    
    @piece_mat[LIGHT] = 0;
    @piece_mat[DARK] = 0;
    @pawn_mat[LIGHT] = 0;
    @pawn_mat[DARK] = 0;
    
    64.times{|i|
      next if (@color[i] == EMPTY)
      if (@piece[i] == PAWN)
        @pawn_mat[@color[i]] += PIECE_VALUE[PAWN];
        f = COL(i) + 1;  #/* add 1 because of the extra file in the array */
        if (@color[i] == LIGHT)
          if (@pawn_rank[LIGHT][f] < ROW(i))
            @pawn_rank[LIGHT][f] = ROW(i)
          end
        else
          if (@pawn_rank[DARK][f] > ROW(i))
            @pawn_rank[DARK][f] = ROW(i)
          end
        end
      else
        @piece_mat[@color[i]] += PIECE_VALUE[@piece[i]];
      end
    }

    # this is the second pass: evaluate each piece 
    score[LIGHT] = @piece_mat[LIGHT] + @pawn_mat[LIGHT];
    score[DARK]  = @piece_mat[DARK] + @pawn_mat[DARK];
    
    64.times{|i|
      next if (@color[i] == EMPTY)
      
      if (@color[i] == LIGHT)
        case (@piece[i])
          when PAWN
            score[LIGHT] += eval_light_pawn(i)
          when KNIGHT
            score[LIGHT] += KNIGHT_PCSQ[i]
          when BISHOP
            score[LIGHT] += BISHOP_PCSQ[i]
          when ROOK
            if (@pawn_rank[LIGHT][COL(i) + 1] == 0)
              if (@pawn_rank[DARK][COL(i) + 1] == 7)
                score[LIGHT] += ROOK_OPEN_FILE_BONUS;
              else
                score[LIGHT] += ROOK_SEMI_OPEN_FILE_BONUS;
              end
            end
            
            score[LIGHT] += ROOK_ON_SEVENTH_BONUS if (ROW(i) == 1)
          when KING
            if (@piece_mat[DARK] <= 1200)
              score[LIGHT] += KING_ENDGAME_PCSQ[i]
            else
              score[LIGHT] += eval_light_king(i)
            end
        end
      else
        case (@piece[i])
          when PAWN
            score[DARK] += eval_dark_pawn(i)
          when KNIGHT
            score[DARK] += KNIGHT_PCSQ[FLIP[i]]
          when BISHOP
            score[DARK] += BISHOP_PCSQ[FLIP[i]]
          when ROOK
            if (@pawn_rank[DARK][COL(i) + 1] == 7) 
              if (@pawn_rank[LIGHT][COL(i) + 1] == 0)
                score[DARK] += ROOK_OPEN_FILE_BONUS;
              else
                score[DARK] += ROOK_SEMI_OPEN_FILE_BONUS;
              end
            end
            
            score[DARK] += ROOK_ON_SEVENTH_BONUS if (ROW(i) == 6)
          when KING
            if (@piece_mat[LIGHT] <= 1200)
              score[DARK] += KING_ENDGAME_PCSQ[FLIP[i]]
            else
              score[DARK] += eval_dark_king(i)
            end
        end
      end
    }

    # the score[] array is set, now return the score relative
    # to the side to move */
    return score[LIGHT] - score[DARK] if (side == LIGHT)
    return score[DARK] - score[LIGHT]
  end

  def eval_light_pawn(sq)
    #int r;  /* the value to return */
    #int f;  /* the pawn's file */

    r = 0;
    f = COL(sq) + 1;

    r += PAWN_PCSQ[sq];

    #/* if there's a pawn behind this one, it's doubled */
    if (@pawn_rank[LIGHT][f] > ROW(sq))
      r -= DOUBLED_PAWN_PENALTY
    end

    #/* if there aren't any friendly pawns on either side of
    #   this one, it's isolated */
    if ((@pawn_rank[LIGHT][f - 1] == 0) &&
        (@pawn_rank[LIGHT][f + 1] == 0))
      r -= ISOLATED_PAWN_PENALTY;

    # /* if it's not isolated, it might be backwards */
    elsif ((@pawn_rank[LIGHT][f - 1] < ROW(sq)) &&
        (@pawn_rank[LIGHT][f + 1] < ROW(sq)))
      r -= BACKWARDS_PAWN_PENALTY;
    end
    
    #/* add a bonus if the pawn is passed */
    if ((@pawn_rank[DARK][f - 1] >= ROW(sq)) &&
        (@pawn_rank[DARK][f    ] >= ROW(sq)) &&
        (@pawn_rank[DARK][f + 1] >= ROW(sq)))
      r += (7 - ROW(sq)) * PASSED_PAWN_BONUS;
    end
    
    return r;
  end

  def eval_dark_pawn(sq)
    #int r;  /* the value to return */
    #int f;  /* the pawn's file */

    r = 0;
    f = COL(sq) + 1;

    r += PAWN_PCSQ[FLIP[sq]];

    #/* if there's a pawn behind this one, it's doubled */
    if (@pawn_rank[DARK][f] < ROW(sq))
      r -= DOUBLED_PAWN_PENALTY;
    end
    
    #/* if there aren't any friendly pawns on either side of
    #   this one, it's isolated */
    if ((@pawn_rank[DARK][f - 1] == 7) &&
        (@pawn_rank[DARK][f + 1] == 7))
      r -= ISOLATED_PAWN_PENALTY;

    #/* if it's not isolated, it might be backwards */
    elsif ((@pawn_rank[DARK][f - 1] > ROW(sq)) &&
        (@pawn_rank[DARK][f + 1] > ROW(sq)))
      r -= BACKWARDS_PAWN_PENALTY;
    end
    
    # add a bonus if the pawn is passed */
    if ((@pawn_rank[LIGHT][f - 1] <= ROW(sq)) &&
        (@pawn_rank[LIGHT][f    ] <= ROW(sq)) &&
        (@pawn_rank[LIGHT][f + 1] <= ROW(sq)))
      r += ROW(sq) * PASSED_PAWN_BONUS;
    end
    return r;
  end

  def eval_light_king(sq)
    #int r;  /* the value to return */
    #int i;

    r = KING_PCSQ[sq];

    #/* if the king is castled, use a special function to evaluate the
    #   pawns on the appropriate side */
    if (COL(sq) < 3)
      r += eval_lkp(1);
      r += eval_lkp(2);
      r += eval_lkp(3) / 2; # problems with pawns on the c & f files
                            # are not as severe
    elsif (COL(sq) > 4)
      r += eval_lkp(8);
      r += eval_lkp(7);
      r += eval_lkp(6) / 2;
    
    # otherwise, just assess a penalty if there are open files near
    #  the king */
    else 
      i = COL(sq)
      while (i < COL(sq) + 2)
        r -= 10 if ((@pawn_rank[LIGHT][i] == 0) && (@pawn_rank[DARK][i] == 7))
        i += 1
      end
    end

    #/* scale the king safety value according to the opponent's material;
    #   the premise is that your king safety can only be bad if the
    #   opponent has enough pieces to attack you */
    r *= @piece_mat[DARK];
    r /= 3100;

    return r;
  end

  #/* eval_lkp(f) evaluates the Light King Pawn on file f */

  def eval_lkp(f)
    r = 0

    if (@pawn_rank[LIGHT][f] == 6) # /* pawn hasn't moved */
    elsif (@pawn_rank[LIGHT][f] == 5)
      r -= 10; # /* pawn moved one square */
    elsif (@pawn_rank[LIGHT][f] != 0)
      r -= 20; # /* pawn moved more than one square */
    else
      r -= 25; # /* no pawn on this file */
    end

    if (@pawn_rank[DARK][f] == 7)
      r -= 15; # /* no enemy pawn */
    elsif (@pawn_rank[DARK][f] == 5)
      r -= 10; # /* enemy pawn on the 3rd rank */
    elsif (@pawn_rank[DARK][f] == 4)
      r -= 5; #  /* enemy pawn on the 4th rank */
    end

    return r;
  end

  def eval_dark_king(sq)
    #int r;
    #int i;

    r = KING_PCSQ[FLIP[sq]]
    if (COL(sq) < 3)
      r += eval_dkp(1);
      r += eval_dkp(2);
      r += eval_dkp(3) / 2;
    elsif (COL(sq) > 4)
      r += eval_dkp(8)
      r += eval_dkp(7)
      r += eval_dkp(6) / 2
    else 
      i = COL(sq)
      while (i <= COL(sq))
        r -= 10 if ((@pawn_rank[LIGHT][i] == 0) && (@pawn_rank[DARK][i] == 7))
        i += 1
      end
    end
    
    r *= @piece_mat[LIGHT];
    r /= 3100;
    return r;
  end

  def eval_dkp(f)
    r = 0

    if (@pawn_rank[DARK][f] == 1)
    elsif (@pawn_rank[DARK][f] == 2)
      r -= 10;
    elsif (@pawn_rank[DARK][f] != 7)
      r -= 20;
    else
      r -= 25;
    end

    if (@pawn_rank[LIGHT][f] == 0)
      r -= 15;
    elsif (@pawn_rank[LIGHT][f] == 2)
      r -= 10;
    elsif (@pawn_rank[LIGHT][f] == 3)
      r -= 5;
    end

    return r;
  end



  # get_ms() returns the milliseconds elapsed since midnight,
  # January 1, 1970. */

  #BOOL ftime_ok = FALSE;  /* does ftime return milliseconds? */
  def get_ms()
    return (Time.now.to_f * 1000).to_i
    
    #struct timeb timebuffer;
    #ftime(&timebuffer);
    #if (timebuffer.millitm != 0)
    #	ftime_ok = TRUE;
    #return (timebuffer.time * 1000) + timebuffer.millitm;
  end

  # parse the move s (in coordinate notation) and return the move's
  # index in gen_dat, or -1 if the move is illegal

  def parse_move(s)
    #int from, to, i;

    # /* make sure the string looks like a move */
=begin
    if (s[0] < 'a' || s[0] > 'h' ||
        s[1] < '0' || s[1] > '9' ||
        s[2] < 'a' || s[2] > 'h' ||
        s[3] < '0' || s[3] > '9')
      return -1;
=end
    return -1 if s.size < 4
    
    [['a', 'h'], ['0', '9'], 
     ['a', 'h'], ['0', '9']].each_with_index{|(min, max), i|
     return -1 unless s[i].ord.between?(min.ord, max.ord)
    }
    
    from = s[0].ord - 'a'.ord;
    from += 8 * (8 - (s[1].ord - '0'.ord));
    to = s[2].ord - 'a'.ord;
    to += 8 * (8 - (s[3].ord - '0'.ord));

    @first_move[1].times{|i|
      if (@gen_dat[i].m.b.from == from && @gen_dat[i].m.b.to == to)

        # if the move is a promotion, handle the promotion piece;
        # assume that the promotion moves occur consecutively in
        # gen_dat. 
        if CCOND(gen_dat[i].m.b.bits & 32)
          case s[4]
            when 'N' then return i
            when 'B' then return i + 1;
            when 'R' then return i + 2;
            else # /* assume it's a queen */
              return i + 3;
          end
        end
        
        return i
      end
    }
    
    # didn't find the move */
    return -1;
  end


  # move_str returns a string with move m in coordinate notation 
  def move_str(m)
    #static char str[6];
    #char c;

    if CCOND(m.bits & 32)
      case (m.promote)
      when KNIGHT
        c = 'n'.ord
      when BISHOP
        c = 'b'.ord
      when ROOK
        c = 'r'.ord
      else
        c = 'q'.ord
      end
        
      str = sprintf("%c%d%c%d%c",
        COL(m.from) + 'a'.ord,
        8 - ROW(m.from),
        COL(m.to) + 'a'.ord,
        8 - ROW(m.to),
        c
      );
    else
      str = sprintf("%c%d%c%d",
        COL(m.from) + 'a'.ord,
        8 - ROW(m.from),
        COL(m.to) + 'a'.ord,
        8 - ROW(m.to)
      );
    end
      
    return str;
  end


  #/* print_board() prints the board */

  def print_board()
    #int i;
    
    printf("\n8 ")
    64.times{|i|
      case (@color[i]) 
      when EMPTY
        printf(" .")
      when LIGHT
        printf(" %c", PIECE_CHAR[@piece[i]])
      when DARK
        printf(" %c", PIECE_CHAR[@piece[i]].ord + ('a'.ord - 'A'.ord))
      end
      
      if ((i + 1) % 8 == 0 && i != 63)
        printf("\n%d ", 7 - ROW(i));
      end
    }
    printf("\n\n   a b c d e f g h\n\n");
  end
  
  # print_result() checks to see if the game is over, and if so,
  # prints the result. 

  def print_result
    #int i;

    #/* is there a legal move? */
    legal = false
    @first_move[1].times{|i|
      if (makemove(@gen_dat[i].m.b))
        takeback()
        legal = true
        break
      end
    }
    
    if (reps() == 3)
      printf("1/2-1/2 {Draw by repetition}\n");
    elsif (@fifty >= 100)
      printf("1/2-1/2 {Draw by fifty move rule}\n");
    elsif (!legal)
      if (in_check(@side))
        if (@side == LIGHT)
          printf("0-1 {Black mates}\n");
        else
          printf("1-0 {White mates}\n");
        end
      else
        printf("1/2-1/2 {Stalemate}\n");
      end
    end
  end
  
  def xboard
    #int computer_side;
    #char line[256], command[256];
    #int m;
    post = 0;

    #signal(SIGINT, SIG_IGN);
    printf("\n")
    self.init_board()
    self.gen()
    @computer_side = EMPTY;
    
    loop do
      #fflush(stdout)
      $stdout.flush
      
      if (@side == @computer_side)
        self.think(post)
        if !CCOND(@pv[0][0].u)
          @computer_side = EMPTY;
          next
        end
        printf("move %s\n", move_str(@pv[0][0].b));
        makemove(@pv[0][0].b);
        @ply = 0
        gen()
        self.print_result()
        next
      end
      
      command = gets.chop
      next if command.empty?
      
      case command
      when "xboard"
        next
      when "new"
        self.init_board
        self.gen
        @computer_side = DARK
        next
      when "quit"
        return
      when "force"
        @computer_side = EMPTY
        next
      when "white"
        @side = LIGHT
        @xside = DARK
        self.gen
        @computer_side = DARK
        next
      when "black"
        @side = DARK
        @xside = LIGHT
        self.gen
        @computer_side = LIGHT
        next
      when /st (\d+)/
        @max_time = $1.to_i * 1000
        @max_depth = 32

      when /sd (\d+)/
        @max_depth = $1.to_i
        @max_time = 1 << 25
        next
      when /time (\d+)/
        @max_time = $1.to_i
        @max_time *= 10
        @max_time /= 30
        @max_depth = 32
      when "otim"
        next
      when "go"
        @computer_side = @side
        next
      when "hint"
        self.think(0)
        next if !CCOND(@pv[0][0].u)
        printf("Hint: %s\n", move_str(@pv[0][0].b));
        next
      when "undo"
        next if !CCOND(@hply)
        self.takeback()
        @ply = 0;
        self.gen()
        next
      when "remove"
        next if (@hply < 2)
        self.takeback
        self.takeback
        @ply = 0
        self.gen
        next
      when "post"
        post = 2
        next
      when "nopost"
        post = 0
        next
      end
      
      m = parse_move(command)
      if (m == -1 || !makemove(@gen_dat[m].m.b))
        printf("Error (unknown command): %s\n", command);
      else
        @ply = 0
        self.gen()
        self.print_result()
      end
    end
	end
  
  attr_accessor :ply, :computer_side, :max_time, :max_depth, :side, :pv, :gen_dat
  
  def undo
    return if !CCOND(@hply)
    @computer_side = EMPTY;
    self.takeback
    @ply = 0
    self.gen
  end
  
  def newGame
    @computer_side = EMPTY
    self.init_board
    self.gen
  end
end

#=====================
# MAIN LOOP : USAGE
#=====================

if ($0 == __FILE__)
	include TSCPConsts
	chess = TSCP.new

	loop do
		if (chess.side == chess.computer_side)  # computer's turn 
			#  think about the move and make it
			chess.think(1);
			if !CCOND(chess.pv[0][0].u)
				printf("(no legal moves)\n");
				chess.computer_side = EMPTY;
				next
			end
			printf("Computer's move: %s\n", chess.move_str(chess.pv[0][0].b));
			chess.makemove(chess.pv[0][0].b);
			chess.ply = 0;
			chess.gen();
			chess.print_result();
			next
		end

		# get user input
		printf("tscp> ");
		s = gets.chomp
		if s.empty?
			printf("\n")
			next 
		end
		
		case s
		when "on"
			chess.computer_side = chess.side;
			next
		when "off"
			chess.computer_side = EMPTY;
			next
		when /st\s+(\d+)/
			chess.max_time = $1.to_i * 1000
			chess.max_depth = 32
			next
		when /sd\s+(\d+)/
			chess.max_depth = $1.to_i
			chess.max_time = 1 << 25
			next
		when "undo"
			chess.undo()
			next
		when "new"
			chess.newGame
			next
		when "d"
			chess.print_board();
			next
		when "bye"
			printf("Share and enjoy!\n");
			break;
		when "xboard"
			chess.xboard
			break
		when "help"
			printf("on - computer plays for the side to move\n");
			printf("off - computer stops playing\n");
			printf("st n - search for n seconds per move\n");
			printf("sd n - search n ply per move\n");
			printf("undo - takes back a move\n");
			printf("new - starts a new game\n");
			printf("d - display the board\n");
			printf("bye - exit the program\n");
			printf("Enter moves in coordinate notation, e.g., e2e4, e7e8Q\n");
			next
		end

		# maybe the user entered a move?
		m = chess.parse_move(s);
		if (m == -1 || !chess.makemove(chess.gen_dat[m].m.b))
			printf("Illegal move.\n");
		else
			chess.ply = 0;
			chess.gen()
			chess.print_result()
		end
	end

	chess.close_book();
end