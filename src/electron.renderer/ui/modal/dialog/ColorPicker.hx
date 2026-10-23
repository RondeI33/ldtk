package ui.modal.dialog;

class ColorPicker extends ui.modal.Dialog {
	var picker : ui.HueWheelPicker;
	var ready = false;
	var validated = false;
	var originalInputValue : Null<String>;
	var jTargetInput : js.jquery.JQuery;
	var originalColor : Int;
	var usedColorsTag : Null<String>;
	var nullable = false;

	public function new(?usedColorsTag:String, ?suggestedColors:Array<dn.Col>, ?jTarget:js.jquery.JQuery, ?color:dn.Col, allowNull=false) {
		super(jTarget);

		this.usedColorsTag = usedColorsTag;
		loadTemplate("colorPicker");

		if( jTarget!=null && jTarget.is("input") ) {
			jTargetInput = jTarget;
			originalInputValue = jTarget.val();
		}

		var jPreview = jContent.find(".preview");

		// Manual text input
		var jInput = jContent.find(".input input");
		var editingHex = false;
		jInput
			.on("change keyup", (ev:js.jquery.Event)->{
				if( jInput.val().indexOf("#")>=0 )
					jInput.val( StringTools.replace(jInput.val(), "#", "") );

				if( C.isValidHex( jInput.val() ) ) {
					editingHex = true;
					picker.setColor( C.sanitizeHexStr( jInput.val() ) );
					editingHex = false;
				}
			})
			.on( "blur", ev->jInput.val( picker.getHexString().substr(1) ) );

		// Paste from clipboard
		jContent.find(".paste").click( (ev:js.jquery.Event)->{
			var cb = electron.Clipboard.readText();
			if( C.isValidHex(cb) ) {
				picker.setColor( C.sanitizeHexStr( cb ) );
				N.quick("Pasted color");
			}
		});
		updatePaste();

		// Copy to clipboard
		jContent.find(".copy").click( (ev:js.jquery.Event)->{
			electron.Clipboard.writeText( picker.getHexString() );
			ev.getThis().addClass("done");
			N.copied();
			updatePaste();
		});

		// Nullable
		if( allowNull ) {
			nullable = true;
			jContent.find(".nullify").click(_->{
				validated = true;
				onValidate(null);
				close();
			});
		}
		else
			jContent.find(".nullify").hide();

		var jExpand = jContent.find(".recentColors .expand");
		var jRecents = jContent.find(".recentColors .recents");
		if( usedColorsTag!=null ) {
			// Recently used colors
			var showAll = false;
			function _updateRecents() {
				jRecents.empty();
				jExpand.removeClass("on");
				jExpand.removeClass("off");
				if( showAll )
					jExpand.addClass("showAll");
				else
					jExpand.removeClass("showAll");

				if( settings.getUiStateBool(ShowProjectColors) && usedColorsTag!=null ) {
					// Update recent colors list
					var usedColors = project.getUsedColorsAsArray(showAll ? null : usedColorsTag);
					for( c in usedColors ) {
						var jC = new J('<div class="color"/>');
						jC.css("background-color", C.intToHex(c));
						jC.appendTo(jRecents);
						jC.click((_)->{
							picker.setColor(c);
							jInput.val( C.intToHex(c,false) );
						});
					}
					if( usedColors.length==0 ) {
						jRecents.addClass("empty");
						jRecents.append("Empty");
					}
					else {
						// Show all button
						if( !showAll ) {
							var jShowAll = new J('<a class="showAll">Show all colors used in this project</a>');
							jShowAll.click(_->{
								showAll = true;
								_updateRecents();
							});
							jShowAll.appendTo(jRecents);
						}
						jRecents.removeClass("empty");
					}

					jExpand.addClass("on");
				}
				else
					jExpand.addClass("off");
			}
			jExpand.click( _->{
				settings.toggleUiStateBool(ShowProjectColors);
				settings.save();
				if( settings.getUiStateBool(ShowProjectColors) )
					jExpand.next().slideDown(100).css('display','grid');
				else
					jExpand.next().slideUp(60);
				_updateRecents();
			});
			_updateRecents();
		}
		else if( suggestedColors!=null ) {
			// Suggested palette
			jExpand.hide();
			for( c in suggestedColors ) {
				var jC = new J('<div class="color"/>');
				jC.css("background-color", c.toHex());
				jC.appendTo(jRecents);
				jC.click((_)->{
					picker.setColor(c);
					jInput.val( c.toHex(false) );
				});
			}
		}
		else {
			jExpand.hide();
			jRecents.hide();
		}


		// Color picker
		picker = new ui.HueWheelPicker();
		picker.appendTo( jContent.find(".picker").get(0) );
		picker.onChange( c->{
			// Hex, RGB, wheel, square, well and live canvas tint share one value.
			if( !editingHex || picker.isChoosing )
				jInput.val( c.substr(1) );
			var rgb = picker.getHexNumber();
			jContent.find(".rgb .red").val((rgb>>16)&255);
			jContent.find(".rgb .green").val((rgb>>8)&255);
			jContent.find(".rgb .blue").val(rgb&255);
			jContent.find(".copy").removeClass("done");
			jPreview.css({ backgroundColor:c });
			if( ready ) {
				if( jTargetInput!=null )
					jTargetInput.val(c).trigger("colorpreview");
				onPreview(rgb);
			}
		});
		jContent.find(".rgb input").on("input change", (_:js.jquery.Event)->{
			var r = Std.parseInt(jContent.find(".rgb .red").val());
			var g = Std.parseInt(jContent.find(".rgb .green").val());
			var b = Std.parseInt(jContent.find(".rgb .blue").val());
			if( r==null || g==null || b==null ) return;
			picker.setColor((M.iclamp(r,0,255)<<16) | (M.iclamp(g,0,255)<<8) | M.iclamp(b,0,255));
		});

		// Init color
		if( color!=null )
			picker.setColor(color);
		else if( jTargetInput!=null )
			picker.setColor( jTargetInput.val() );
		originalColor = getColor();

		// Init elements
		if( nullable && color==null )
			jInput.val("");
		else
			jInput.val( picker.getHexString().substr(1) );
		jInput.focus().select();
		jPreview.css({ backgroundColor:picker.getHexString() });

		JsTools.parseComponents(jContent);
		ready = true;
	}

	function updatePaste() {
		var jPaste = jContent.find(".paste");
		if( C.isValidHex( electron.Clipboard.readText() ) ) {
			jPaste.addClass("enabled");
			jPaste.css({ backgroundColor: C.sanitizeHexStr(electron.Clipboard.readText()) });
		}
		else
			jPaste.removeClass("enabled");
	}

	override function onKeyPress(keyCode:Int) {
		super.onKeyPress(keyCode);

		switch keyCode {
			case K.ESCAPE:
				validate();
				close();

			case K.ENTER:
				validate();
				close();
		}
	}

	function validate() {
		if( validated ) return;
		validated = true;
		if( jTargetInput!=null )
			jTargetInput.val( picker.getHexString() ).trigger("colorpreviewend").change();

		if( usedColorsTag!=null ) {
			project.unregisterColor( usedColorsTag, originalColor );
			project.registerUsedColor( usedColorsTag, getColor() );
		}
		onValidate( getColor() );
	}

	public dynamic function onValidate(c:dn.Col) {}
	public dynamic function onPreview(c:dn.Col) {}
	public dynamic function onCancel() {}

	override function onClickMask() {
		validate();
		super.onClickMask();
	}

	override function onDispose() {
		ready = false;
		if( jTargetInput!=null ) {
			if( !validated ) jTargetInput.val(originalInputValue);
			jTargetInput.trigger("colorpreviewend");
		}
		if( !validated ) onCancel();
		super.onDispose();
		if( picker!=null ) picker.remove();
		picker = null;
	}

	public function getColor() {
		return picker.getHexNumber();
	}
}
