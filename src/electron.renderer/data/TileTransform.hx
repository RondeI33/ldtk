package data;

/**
 * Square-tile orientation used inside the editor. Bits 0/1 mirror the result
 * along X/Y; bit 2 transposes X/Y before those mirrors. The extra bit lives in
 * the fork sidecar on disk, never in the native LDtk flip field.
 */
class TileTransform {
	public static inline var TRANSPOSE = 4;

	public static inline function isTransposed(flips:Int) : Bool {
		return (flips & TRANSPOSE)!=0;
	}

	public static inline function nativeFlips(flips:Int) : Int {
		return flips & 3;
	}

	public static inline function rotate(flips:Int, clockwise:Bool) : Int {
		var x = (flips & 2)>>1;
		var y = (flips & 1)<<1;
		return (x | y | ((flips ^ TRANSPOSE)&TRANSPOSE)) ^ (clockwise ? 1 : 2);
	}

	/** Apply an outer world-space orientation after the tile's current one. */
	public static inline function compose(flips:Int, transform:Int) : Int {
		var inner = isTransposed(transform)
			? ((flips & 1)<<1) | ((flips & 2)>>1) | ((flips ^ TRANSPOSE)&TRANSPOSE)
			: flips;
		return inner ^ (transform & 3);
	}

	/** Add a tile whose untransformed bounds start at (x,y), rotating about the cell centre. */
	public static function render(tg:h2d.TileGroup, tile:h2d.Tile, x:Float, y:Float, grid:Float, flips:Int) {
		var sx = (flips & 1)!=0 ? -1 : 1;
		var sy = (flips & 2)!=0 ? -1 : 1;
		var tx = x + (sx<0 ? grid : 0);
		var ty = y + (sy<0 ? grid : 0);
		if( isTransposed(flips) )
			tg.addTransform(tx, ty, sy, -sx, Math.PI/2, tile);
		else
			tg.addTransform(tx, ty, sx, sy, 0, tile);
	}

	/** A private tile view keeps shared atlas-tile origin values unchanged. */
	public static inline function withCellPivot(tile:h2d.Tile, grid:Float, pivotX:Float, pivotY:Float) : h2d.Tile {
		return tile.sub(0,0,tile.width,tile.height,(grid-tile.width)*pivotX,(grid-tile.height)*pivotY);
	}

	public static function placeBitmap(bmp:h2d.Bitmap, x:Float, y:Float, grid:Float, flips:Int) {
		var sx = (flips & 1)!=0 ? -1 : 1;
		var sy = (flips & 2)!=0 ? -1 : 1;
		bmp.x = x + (sx<0 ? grid : 0);
		bmp.y = y + (sy<0 ? grid : 0);
		bmp.scaleX = isTransposed(flips) ? sy : sx;
		bmp.scaleY = isTransposed(flips) ? -sx : sy;
		bmp.rotation = isTransposed(flips) ? Math.PI/2 : 0;
	}
}
