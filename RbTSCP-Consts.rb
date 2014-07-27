module TSCPConsts
  class MoveBytes
    def initialize(buffer)
      @buffer = buffer
    end
    
    [:from, :to, :promote, :bits].each_with_index{|meth, i|
      define_method(meth){
        return @buffer[i]
      }
      
      define_method("#{meth}="){|v|
        @buffer[i] = v
      }
    }
  end

  class Move
    def initialize
      @buffer    = DL::CPtr.malloc(4)
      @moveBytes = MoveBytes.new(@buffer)
    end
    
    def u
      @buffer.ptr.to_i
    end
    
    def b
      @moveBytes
    end
    
    def u=(v)
      @buffer[0,4] = [v].pack("l")
    end
    
    def b=(v)
      @buffer[0,4] = [v.from, v.to, v.promote, v.bits].pack("c4")
    end
  end

  class Gen_t < Struct.new(:m, :score)
    def initialize
      super(Move.new, 0)
    end
  end

  class Hist_t < Struct.new(:m, :capture, :castle, :ep, :fifty, :hash)
    def initialize
      super(Move.new, 0, 0, 0, 0, 0)
    end
  end
  
=begin
     Now we have the mailbox array, so called because it looks like a
     mailbox, at least according to Bob Hyatt. This is useful when we
     need to figure out what pieces can go where. Let's say we have a
     rook on square a4 (32) and we want to know if it can move one
     square to the left. We subtract 1, and we get 31 (h5). The rook
     obviously can't move to h5, but we don't know that without doing
     a lot of annoying work. Sooooo, what we do is figure out a4's
     mailbox number, which is 61. Then we subtract 1 from 61 (60) and
     see what mailbox[60] is. In this case, it's -1, so it's out of
     bounds and we can forget it. You can see how mailbox[] is used
     in attack() in board.c.
=end

  MAILBOX = [
     -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
     -1,  0,  1,  2,  3,  4,  5,  6,  7, -1,
     -1,  8,  9, 10, 11, 12, 13, 14, 15, -1,
     -1, 16, 17, 18, 19, 20, 21, 22, 23, -1,
     -1, 24, 25, 26, 27, 28, 29, 30, 31, -1,
     -1, 32, 33, 34, 35, 36, 37, 38, 39, -1,
     -1, 40, 41, 42, 43, 44, 45, 46, 47, -1,
     -1, 48, 49, 50, 51, 52, 53, 54, 55, -1,
     -1, 56, 57, 58, 59, 60, 61, 62, 63, -1,
     -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
     -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
  ]
  MAILBOX64 = [
    21, 22, 23, 24, 25, 26, 27, 28,
    31, 32, 33, 34, 35, 36, 37, 38,
    41, 42, 43, 44, 45, 46, 47, 48,
    51, 52, 53, 54, 55, 56, 57, 58,
    61, 62, 63, 64, 65, 66, 67, 68,
    71, 72, 73, 74, 75, 76, 77, 78,
    81, 82, 83, 84, 85, 86, 87, 88,
    91, 92, 93, 94, 95, 96, 97, 98
  ]

=begin
     slide, offsets, and offset are basically the vectors that
     pieces can move in. If slide for the piece is FALSE, it can
     only move one square in any one direction. offsets is the
     number of directions it can move in, and offset is an array
     of the actual directions.
=end

  SLIDE = [
    false, false, true, true, true, false
  ]

  OFFSETS = [
    0, 8, 4, 4, 8, 8
  ]

  OFFSET = [
    [ 0, 0, 0, 0, 0, 0, 0, 0 ],
    [ -21, -19, -12, -8, 8, 12, 19, 21 ],
    [ -11, -9, 9, 11, 0, 0, 0, 0 ],
    [ -10, -1, 1, 10, 0, 0, 0, 0 ],
    [ -11, -10, -9, -1, 1, 9, 10, 11 ],
    [ -11, -10, -9, -1, 1, 9, 10, 11 ]
  ]


=begin
     This is the castle_mask array. We can use it to determine
     the castling permissions after a move. What we do is
     logical-AND the castle bits with the castle_mask bits for
     both of the move's squares. Let's say castle is 1, meaning
     that white can still castle kingside. Now we play a move
     where the rook on h1 gets captured. We AND castle with
     castle_mask[63], so we have 1&14, and castle becomes 0 and
     white can't castle kingside anymore.
=end
  CASTLE_MASK = [
     7, 15, 15, 15,  3, 15, 15, 11,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15,
    13, 15, 15, 15, 12, 15, 15, 14
  ]


  # the piece letters, for print_board() */
  PIECE_CHAR = [
    'P', 'N', 'B', 'R', 'Q', 'K'
  ]


  # the initial board state

  INIT_COLOR = [
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
  ]

  INIT_PIECE = [
    3, 1, 2, 4, 5, 2, 1, 3,
    0, 0, 0, 0, 0, 0, 0, 0,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    0, 0, 0, 0, 0, 0, 0, 0,
    3, 1, 2, 4, 5, 2, 1, 3
  ]
  
  DOUBLED_PAWN_PENALTY = 10
  ISOLATED_PAWN_PENALTY	= 20
  BACKWARDS_PAWN_PENALTY = 8
  PASSED_PAWN_BONUS	= 20
  ROOK_SEMI_OPEN_FILE_BONUS	= 10
  ROOK_OPEN_FILE_BONUS = 15
  ROOK_ON_SEVENTH_BONUS	= 20


  # the values of the pieces 
  PIECE_VALUE = [
    100, 300, 300, 500, 900, 0
  ]

  # The "pcsq" arrays are piece/square tables. They're values
  #   added to the material value of the piece based on the
  #   location of the piece. */

  PAWN_PCSQ = [
      0,   0,   0,   0,   0,   0,   0,   0,
      5,  10,  15,  20,  20,  15,  10,   5,
      4,   8,  12,  16,  16,  12,   8,   4,
      3,   6,   9,  12,  12,   9,   6,   3,
      2,   4,   6,   8,   8,   6,   4,   2,
      1,   2,   3, -10, -10,   3,   2,   1,
      0,   0,   0, -40, -40,   0,   0,   0,
      0,   0,   0,   0,   0,   0,   0,   0
  ]

  KNIGHT_PCSQ = [
    -10, -10, -10, -10, -10, -10, -10, -10,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10,   0,   5,   5,   5,   5,   0, -10,
    -10,   0,   5,  10,  10,   5,   0, -10,
    -10,   0,   5,  10,  10,   5,   0, -10,
    -10,   0,   5,   5,   5,   5,   0, -10,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10, -30, -10, -10, -10, -10, -30, -10
  ]

  BISHOP_PCSQ = [
    -10, -10, -10, -10, -10, -10, -10, -10,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10,   0,   5,   5,   5,   5,   0, -10,
    -10,   0,   5,  10,  10,   5,   0, -10,
    -10,   0,   5,  10,  10,   5,   0, -10,
    -10,   0,   5,   5,   5,   5,   0, -10,
    -10,   0,   0,   0,   0,   0,   0, -10,
    -10, -10, -20, -10, -10, -20, -10, -10
  ]

  KING_PCSQ = [
    -40, -40, -40, -40, -40, -40, -40, -40,
    -40, -40, -40, -40, -40, -40, -40, -40,
    -40, -40, -40, -40, -40, -40, -40, -40,
    -40, -40, -40, -40, -40, -40, -40, -40,
    -40, -40, -40, -40, -40, -40, -40, -40,
    -40, -40, -40, -40, -40, -40, -40, -40,
    -20, -20, -20, -20, -20, -20, -20, -20,
      0,  20,  40, -20,   0, -20,  40,  20
  ]

  KING_ENDGAME_PCSQ = [
      0,  10,  20,  30,  30,  20,  10,   0,
     10,  20,  30,  40,  40,  30,  20,  10,
     20,  30,  40,  50,  50,  40,  30,  20,
     30,  40,  50,  60,  60,  50,  40,  30,
     30,  40,  50,  60,  60,  50,  40,  30,
     20,  30,  40,  50,  50,  40,  30,  20,
     10,  20,  30,  40,  40,  30,  20,  10,
      0,  10,  20,  30,  30,  20,  10,   0
  ]

  # The flip array is used to calculate the piece/square
  #   values for DARK pieces. The piece/square value of a
  #   LIGHT pawn is pawn_pcsq[sq] and the value of a DARK
  #   pawn is pawn_pcsq[flip[sq]] */
  FLIP = [
     56,  57,  58,  59,  60,  61,  62,  63,
     48,  49,  50,  51,  52,  53,  54,  55,
     40,  41,  42,  43,  44,  45,  46,  47,
     32,  33,  34,  35,  36,  37,  38,  39,
     24,  25,  26,  27,  28,  29,  30,  31,
     16,  17,  18,  19,  20,  21,  22,  23,
      8,   9,  10,  11,  12,  13,  14,  15,
      0,   1,   2,   3,   4,   5,   6,   7
  ]
  
  RAND_MAX   = 0xFFFFFF

  GEN_STACK  = 1120
  MAX_PLY    = 32
  HIST_STACK = 400

  LIGHT  = 0
  DARK   = 1

  PAWN   = 0
  KNIGHT = 1
  BISHOP = 2
  ROOK   = 3
  QUEEN  = 4
  KING   = 5
  EMPTY  = 6

  #/* useful squares */
  A1, B1, C1, D1, E1, F1, G1, H1 = 56, 57, 58, 59, 60, 61, 62, 63
  A8, B8, C8, D8, E8, F8, G8, H8 =  0,  1,  2,  3,  4,  5,  6,  7

  module_function
  
  def ROW(x)
    x >> 3
  end

  def COL(x)
    x & 7
  end

  def CCOND(x)
    return ((x != 0) && x)
  end
end
