
description = "Russian FFF Machine v2.1";
vendor = "Cbat/DadaPasha";
certificationLevel = 2;
minimumRevision = 45633;

longDescription = "Shows print time in HMS. Supports fractional FAN speed and FAN speed change. Supports main model extruder override (use Ext #2 for main model printing). NB! supports and raft use Ext #2 while extruder override enabled";

extension = "gcode";
setCodePage("ascii");

capabilities = CAPABILITY_ADDITIVE;
tolerance = spatial(0.002, MM);
highFeedrate = (unit == MM) ? 6000 : 236;

// needed for range checking, will be effectively passed from Fusion
var printerLimits = {
  x: {min: 0, max: 300.0}, //Defines the x bed size
  y: {min: 0, max: 300.0}, //Defines the y bed size
  z: {min: 0, max: 300.0} //Defines the z bed size
};

var layerNumFanSpeedFlag = false;
var layerNumFanSpeedWriteBlock = false;
var layerTimeFanSpeedFlag = false;
var layerTimeFanSpeedWriteBlock = false;
//var extruderChangeUsed = false
var moveTime = 0;

// user-defined properties
properties = { 
  mainExtruder: "0",
  ext2SwitchCode: "T11 I3",
  overrideExt2SwitchCode: false,
  mainFanSpeedMult: 1.0,
  layerNumFanSpeedOn: false,
  layerNumFanSpeed: 100,
  layerNumFanSpeedMult: 0.1,
  //layerTimeFanSpeedOn: false,
  //layerTimeFanSpeed: 5,
  //layerTimeFanSpeedMult: 0.8,
  enableBeepStart: false,
  enableBeepEnd: false
};

// user-defined property definitions
propertyDefinitions = {
  mainExtruder: {
    title: "Extruder Override",
    description: "------------------THIS IS DIRTY HACK ----------------\nDefault - uses settings from -> Printer setting editor\nExt #2 - print main model, supports and raft with ext #2 (active extruder override in the -> Printer settings editor)",
    group: 1,
    type: "enum",
    values:[
      {title:"Default", id: "0"},
      {title:"Ext #2", id: "1"}
    ]
  },
  ext2SwitchCode: {
	  title: "Custom Ext #2 switch code", 
	  description: "Custom code to switch to Ext #2\nEx. use 'T11 Ix' for Picaso PRO250", 
	  group: 1, 
	  type: "string"},
  overrideExt2SwitchCode: {
	  title: "Use custom Ext #2 switch code?", 
	  description: "Override standard 'T1' command for Ext #2 switch", 
	  group: 1, 
	  type: "boolean"},	  
  mainFanSpeedMult: {
	  title: "FAN speed Multiplier", 
	  description: "Enter a multiplier value to change the main FAN speed.\nExample: 1 = 100%, 0.25 = 25%, 0 = 0%\nThis parameter works if FAN is enabled in -> Machine -> Extruder Configuration", 
	  group: 2, 
	  type: "number"},
  layerNumFanSpeedOn: {
	  title: "Change FAN speed after layer N?", 
	  description: "Enable or disable FAN speed change after layer N", 
	  group: 3, 
	  type: "boolean"},
  layerNumFanSpeed: {
	  title: "Skip N layers before FAN speed change", 
	  description: "Layer number after which the FAN speed changes", 
	  group: 3, 
	  type: "number"},
  layerNumFanSpeedMult: {
	  title: "FAN speed after layer Multiplier", 
	  description: "Enter a multiplier value to change the FAN speed after layer.\nExample: 1 = 100%, 0.25 = 25%, 0 = 0%\nThis parameter only works if the FAN is enabled in the -> Machine -> Extruder Configuration", 
	  group: 3, 
	  type: "number"},
  //layerTimeFanSpeedOn: {title: "FAN speed by time for layer", description: "", group: 4, type: "boolean"},
  //layerTimeFanSpeed: {title: "Layer time print", description: "", group: 4, type: "number"},
  //layerTimeFanSpeedMult: {title: "FAN speed uper layer time  multiply", description: "", group: 4, type: "number"},
  enableBeepStart: {
	  title: "Beep at start", 
	  description: "Turn on a signal when printing starts.", 
	  group: 5, 
	  type: "boolean"},
  enableBeepEnd: {
	  title: "Beep after finish", 
	  description: "Turn on a signal after printing is completed.", 
	  group: 5, 
	  type: "boolean"}

};

var extruderOffsets = [[0, 0, 0], [0, 0, 0]];
var activeExtruder = 0;  //Track the active extruder.

var xyzFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var xFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var yFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var zFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var gFormat = createFormat({prefix: "G", width: 1, zeropad: false, decimals: 0});
var mFormat = createFormat({prefix: "M", width: 2, zeropad: true, decimals: 0});
var tFormat = createFormat({prefix: "T", width: 1, zeropad: false, decimals: 0});
var feedFormat = createFormat({decimals: (unit == MM ? 0 : 1)});
var integerFormat = createFormat({decimals:0});
var dimensionFormat = createFormat({decimals: (unit == MM ? 3 : 4), zeropad: false, suffix: (unit == MM ? "mm" : "in")});

var gMotionModal = createModal({force: true}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange: function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19 //Actually unused
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91

var xOutput = createVariable({prefix: "X"}, xFormat);
var yOutput = createVariable({prefix: "Y"}, yFormat);
var zOutput = createVariable({prefix: "Z"}, zFormat);
var feedOutput = createVariable({prefix: "F"}, feedFormat);
var eOutput = createVariable({prefix: "E"}, xyzFormat);  // Extrusion length
var sOutput = createVariable({prefix: "S", force: true}, xyzFormat);  // Parameter temperature or speed

// Writes the specified block.
function writeBlock() {
  writeWords(arguments);
}

function onOpen() {
//  writeComment("-- onOpen() Start --");
  getPrinterGeometry();

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }
  writeComment("Post processor: " + description + " \ " + vendor);

  writeComment("Printer Name: " + machineConfiguration.getVendor() + " " + machineConfiguration.getModel());
  
  writeComment("Print time: " + xyzFormat.format(printTime) + " sec");

  var hours = Math.floor(xyzFormat.format(printTime) / 60 / 60);
  var minutes = Math.floor(xyzFormat.format(printTime) / 60) - (hours * 60);
  var seconds = xyzFormat.format(printTime) % 60;
  writeComment("Print time: " + hours + 'h ' + minutes + 'm ' + seconds + "s");

  writeComment("width: " + dimensionFormat.format(printerLimits.x.max));
  writeComment("depth: " + dimensionFormat.format(printerLimits.y.max));
  writeComment("height: " + dimensionFormat.format(printerLimits.z.max));
  writeComment("Count of bodies: " + integerFormat.format(partCount));
  writeComment("Version of Fusion: " + getGlobalParameter("version"));
//  writeComment("-- onOpen() End --");
}

function getPrinterGeometry() {
  machineConfiguration = getMachineConfiguration();

  // Get the printer geometry from the machine configuration
  printerLimits.x.min = 0 - machineConfiguration.getCenterPositionX();
  printerLimits.y.min = 0 - machineConfiguration.getCenterPositionY();
  printerLimits.z.min = 0 + machineConfiguration.getCenterPositionZ();

  printerLimits.x.max = machineConfiguration.getWidth() - machineConfiguration.getCenterPositionX();
  printerLimits.y.max = machineConfiguration.getDepth() - machineConfiguration.getCenterPositionY();
  printerLimits.z.max = machineConfiguration.getHeight() + machineConfiguration.getCenterPositionZ();

  extruderOffsets[0][0] = machineConfiguration.getExtruderOffsetX(1);
  extruderOffsets[0][1] = machineConfiguration.getExtruderOffsetY(1);
  extruderOffsets[0][2] = machineConfiguration.getExtruderOffsetZ(1);
  if (numberOfExtruders > 1) {
    extruderOffsets[1] = [];
    extruderOffsets[1][0] = machineConfiguration.getExtruderOffsetX(2);
    extruderOffsets[1][1] = machineConfiguration.getExtruderOffsetY(2);
    extruderOffsets[1][2] = machineConfiguration.getExtruderOffsetZ(2);
  }

}

function onClose() {
//  writeComment("-- onClose() Start --");
  if (properties.mainExtruder == "1" && activeExtruder == 1) { // DIRTY HACK
    writeBlock(tFormat.format(0));
    activeExtruder = 0;
  } 
  if (properties.enableBeepEnd == true) {
    writeBlock("M300 S300 P1000");
  }
  writeComment("END OF GCODE");
//  writeComment("-- onClose() End --");
}

function onComment(message) {
//  writeComment("-- onComment() Start --");
  writeComment(message);
//  writeComment("-- onComment() End --");
}

function onSection() {
//  writeComment("-- onSection() Start --");
  var range = currentSection.getBoundingBox();
  axes = ["x", "y", "z"];
  formats = [xFormat, yFormat, zFormat];
  for (var element in axes) {
    var min = formats[element].getResultingValue(range.lower[axes[element]]);
    var max = formats[element].getResultingValue(range.upper[axes[element]]);
    if (printerLimits[axes[element]].max < max || printerLimits[axes[element]].min > min) {
      error(localize("A toolpath is outside of the build volume."));
    }
  }

  // set unit
  writeBlock(gFormat.format(unit == MM ? 21 : 20));
  writeBlock(gAbsIncModal.format(90)); // absolute spatial co-ordinates
  writeBlock(mFormat.format(82)); // absolute extrusion co-ordinates

  //homing
  writeRetract(Z); // retract in Z

  //lower build plate before homing in XY
  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  writeBlock(gMotionModal.format(1), zOutput.format(initialPosition.z), feedOutput.format(highFeedrate));

  writeRetract(X, Y);
  writeBlock(gFormat.format(92), eOutput.format(0));

  if (properties.enableBeepStart == true) {
    writeBlock("M300 S300 P1000");
  }
//  writeComment("-- onSection() End --");
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock(gMotionModal.format(0), x, y, z);
  }
}


function onLinearExtrude(_x, _y, _z, _f, _e) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(_f);
  var e = eOutput.format(_e);
  if (x || y || z || f || e) {
    writeBlock(gMotionModal.format(1), x, y, z, f, e);
  }
}

function onBedTemp(temp, wait) {
  if (wait) {
    writeBlock(mFormat.format(190), sOutput.format(temp));
  } else {
    writeBlock(mFormat.format(140), sOutput.format(temp));
  }
}

function onExtruderChange(id) {
//  writeComment("-- onExtruderChange() Start --");
//  extruderChangeUsed = true;
  if (id <= 1 && properties.mainExtruder == "0") {
    writeBlock(tFormat.format(id));
    activeExtruder = id;
    xOutput.reset();
    yOutput.reset();
    zOutput.reset();
  } else if (id <= 1 && properties.mainExtruder == "1") { // DIRTY HACK
    if (properties.overrideExt2SwitchCode) {
		writeBlock(properties.ext2SwitchCode);
	} else {	
		writeBlock(tFormat.format(1));
	}
    activeExtruder = 1;
    xOutput.reset();
    yOutput.reset();
    zOutput.reset();
  } 
//  writeComment("-- onExtruderChange() End --");
}

function onExtrusionReset(length) {
//  writeComment("-- onExtrusionReset() Start --");
  eOutput.reset();
  writeBlock(gFormat.format(92), eOutput.format(length));
//  writeComment("-- onExtrusionReset() End --");
}

 

function onLayer(num) {
//  writeComment("-- onLayer() Start --");
  writeComment("Layer : " + integerFormat.format(num) + " of " + integerFormat.format(layerCount));
  
  if (properties.mainExtruder == "1" && activeExtruder != 1) { // DIRTY HACK
    if (properties.overrideExt2SwitchCode) {
		writeBlock(properties.ext2SwitchCode);
	} else {	
		writeBlock(tFormat.format(1));
	}
    activeExtruder = 1;
  } 

  if (integerFormat.format(num) > 1) {
    if (properties.layerNumFanSpeedOn && (properties.layerNumFanSpeed + 1 <= integerFormat.format(num)) && layerTimeFanSpeedWriteBlock == false) {
      if (layerNumFanSpeedWriteBlock == false) {layerNumFanSpeedFlag = true;} else {layerNumFanSpeedFlag = false;}
    } else {
      layerNumFanSpeedFlag = false;
      layerNumFanSpeedWriteBlock = false;
    }
    // Can't make Hack. Have no time anchor.
    // if (properties.layerTimeFanSpeedOn && (properties.layerTimeFanSpeed >= (xyzFormat.format(printTime) / integerFormat.format(layerCount))) && layerNumFanSpeedWriteBlock == false) { //EXTRA DIRTY HACK
    //   if (layerTimeFanSpeedWriteBlock == false) {layerTimeFanSpeedFlag = true;} else {layerTimeFanSpeedFlag = false;}
    // } else {
    //   layerTimeFanSpeedFlag = false;
    //   layerTimeFanSpeedWriteBlock = false;
    // }
    // if (layerTimeFanSpeedFlag) {
    //   writeBlock(mFormat.format(106), sOutput.format(Math.round(255 * properties.layerTimeFanSpeedMult)));
    //   layerTimeFanSpeedWriteBlock = true;
    //} else if (layerNumFanSpeedFlag) {
    if (layerNumFanSpeedFlag) {
      writeBlock(mFormat.format(106), sOutput.format(Math.round(255 * properties.layerNumFanSpeedMult)));
      layerNumFanSpeedWriteBlock = true;
    }
  }
//  writeComment("-- onLayer() End --");
}

function onExtruderTemp(temp, wait, id) {
//  writeComment("-- onExtruderTemp() Start --");
  if (id <= 1 && properties.mainExtruder == "0") {
    if (wait) {
      writeBlock(mFormat.format(109), sOutput.format(temp), tFormat.format(id));
    } else {
      writeBlock(mFormat.format(104), sOutput.format(temp), tFormat.format(id));
    }
  } else if (id <= 1 && properties.mainExtruder == "1") { // DIRTY HACK
    if (wait) {
      writeBlock(mFormat.format(109), sOutput.format(temp), tFormat.format(1));
    } else {
      writeBlock(mFormat.format(104), sOutput.format(temp), tFormat.format(1));
    }
  } 
//  writeComment("-- onExtruderTemp() End --");
}

function onFanSpeed(speed, id) {
  // to do handle id information
  if (speed == 0) {
    writeBlock(mFormat.format(107));
  }  else if (layerNumFanSpeedFlag == false && layerTimeFanSpeedFlag == false) {
    writeBlock(mFormat.format(106), sOutput.format(Math.round(speed * properties.mainFanSpeedMult)));
  }
}


function onParameter(name, value) {
  switch (name) {
  //feedrate is set before rapid moves and extruder change
  case "feedRate":
    if (unit == IN) {
      value /= 25.4;
    }
    setFeedRate(value);
    break;
  //warning or error message on unhandled parameter?
  }
}

//user defined functions
function setFeedRate(value) {
  feedOutput.reset();
  writeBlock(gFormat.format(1), feedOutput.format(value));
}

function writeComment(text) {
  writeln(";" + text);
}

/** Output block to do safe retract and/or move to home position. */
function writeRetract() {
//  writeComment("-- writeRetract() Start --");	
  if (arguments.length == 0) {
    error(localize("No axis specified for writeRetract()."));
    return;
  }
  var words = []; // store all retracted axes in an array
  for (var i = 0; i < arguments.length; ++i) {
    let instances = 0; // checks for duplicate retract calls
    for (var j = 0; j < arguments.length; ++j) {
      if (arguments[i] == arguments[j]) {
        ++instances;
      }
    }
    if (instances > 1) { // error if there are multiple retract calls for the same axis
      error(localize("Cannot retract the same axis twice in one line"));
      return;
    }
    switch (arguments[i]) {
    case X:
      words.push("X" + xyzFormat.format(machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : 0));
      xOutput.reset();
      break;
    case Y:
      words.push("Y" + xyzFormat.format(machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : 0));
      yOutput.reset();
      break;
    case Z:
      words.push("Z" + xyzFormat.format(0));
      zOutput.reset();
      retracted = true; // specifies that the tool has been retracted to the safe plane
      break;
    default:
      error(localize("Bad axis specified for writeRetract()."));
      return;
    }
  }
  if (words.length > 0) {
    gMotionModal.reset();
    writeBlock(gFormat.format(28), gAbsIncModal.format(90), words); // retract
  }
//  writeComment("-- writeRetract() End --");
}
