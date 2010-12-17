/*
Sketch:		GrOW Controller
Version:	0.1
Status:         In progress
Date:           17 december 2010
Author:		@ArnoJansen for @sindono 
License:        To be determined, but for now its completely open.
Contact:	www.sindono.com

Description:
This project was inspired by an article in Make Magazine, called Garduino.
This program monitors and controls the environment in a greenhouse or vegetable garden. Besides keeping the environment optimal for growth, it reports about its measurements and actions wirelessly to a receiving, internet enabled gateway unit.

Note:
This controller sketch sends measurements wirelessly via Xbee to a GrOW_Gateway. The gateway connects to the internet via ethernet.

Supported sensors:
Attribute	| Sensor	| Range
----------------+---------------+------------
Temperature	| AD TMP36	| -40 - 125 C
Ambient Light	| LDR Photocell | 0 (Dark) - 999 (Light)
Soil Moisture 	| Resistance	| 0 (Dry)  - 999 (Wet)

Future sensors:
Attribute	| Sensor	| Range
----------------+---------------+------------
pH sensor	| unknown	| 

Supported actuators:
Attribute	| Actuator	| Range
----------------+---------------+------------
Temperature	| 4x Servo (*)	| 0 (Close) / 1 (Open)
Ambient Light	| Lights	| 1 (OFF) / 0 (ON)
Soil Moisture 	| Pump		| 1 (OFF) / 0 (ON)

Future actuators:
Attribute	| Actuator	| Range
----------------+---------------+------------
Temperature	| Heater	| 0 (OFF) / 1 (ON)


(*) 4 Servo's are used to open different glass roofpane's in the greenhouse if it gets too hot inside.

This sketch is designed to run on an Arduino Duemilanove with Atmel 328p and an Xbee-shield with a Series 2 Xbee radio setup in API mode.

More information about setup, schema's, protocol, etc can be found at: sindono.com/projects/grow

Known issues / TODO:
- Create a setActuator(actuator, targetState) function. It sets the state of the actuator, updates the switchState accordingly
- Alarm mechanism not implemented. Alarms are currently not raised. 
- Add DCF clock for real time (as opposed to relative time)
- Add pH sensor
- Add Heater actuator
- Add On/Off switch function for doors so servo's ease into position smoothly
- Is it possible to connect +5 to a digital pin, so that servo power can be switched off
  That saves some power, so the Signal and +5V can be switched off once the servo is in position
  
*/

#include <XBee.h>	// Library used from code.google.com/Xbee-Api
#include <Time.h>
#include <Servo.h> 

#define DeviceName "GROW1"
#define ON true
#define OFF false
#define OPEN 0 // set door servo's predetermined positions
#define CLOSE 180
//---------------------------------------------
// Development help
// set Debugging only to true when developping. It prints log message to serial out
// cannot be used in combination with XBee transmissions
//---------------------------------------------
#define debugging false 


//---------------------------------------------
// Create the XBee object
XBee xbee = XBee();

// Put the string with the logdata into the payload
uint8_t payload[] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

// SH + SL Address of receiving XBee
XBeeAddress64 addr64 = XBeeAddress64(0x0013a200, 0x403a8c15);      // Xbee address 
ZBTxRequest zbTx = ZBTxRequest(addr64, payload, sizeof(payload));
ZBTxStatusResponse txStatus = ZBTxStatusResponse();

//decide how many hours of light your plants should get daily
float hours_light_daily_desired = 10;

//calculate desired hours of light total and supplemental daily based on above values
float proportion_to_light = hours_light_daily_desired / 24;
float seconds_light = 0;
float proportion_lit;

//setup a variable to store seconds since arduino switched on
time_t start_time;
float seconds_elapsed;
float seconds_elapsed_total;
float seconds_for_this_cycle;

// Setup threshold values
// Preferrably, these values will be stored in non-volatile memory and could be manipulated
// at a later stage with a web interface or something.
int CFGMinTemp = 21; 		// Minimum temperature in degrees C
int CFGMaxTemp = 23; 		// Maximum temperature in degrees C
int CFGAlarmTemp = 25;                // Alarm/Notification temperature in degrees C
int CFGDayLightLevel = 850;		// Minimum daylight level
int CFGTargetMoistLevel = 850;	// Desired moist level
//int CFGMoistHysteresis = 20;	// Desired moist level
      
   //define variables to store moisture, light, and temperature values
   int moisture_val = 0;			// Analog pins return an int value between 0-1023
   int light_val = 0;
   float temp_val = 0;			// Analog readings from temp sensor are converted to degrees C
   
   // Log interval. The amount of time in milliseconds between sending logs/statistics
   long logInterval = 10000;
   long previousLog = 0; 		// how much time (in millis) has passed since last log

   // Setup input pins for sensors
   // These are ANALOG pins
   int tempSensorPin =  0;
   int lightSensorPin = 1;
   int moistSensorPin = 2;
   int pHSensorPin = 3;		// Future sensor
   
   // Setup output pins for actuators
   // All doors default closed, lights and pump default off.
   // Is it possible to connect LED in circuit to output pins? 
   // That way it is possible to monitor outputs without extra pins for the LED's
   // These are DIGITAL pins
    int lightsPin = 2;
   boolean lightOn = false;
 
   int pumpPin = 4;
   boolean pumpOn =  false;
   
   //int heaterPin = 2;	// Future actuator
   //boolean heaterOn = false;
   
   // The Doors will be opened and closed by servo's. Those require a PWM signal:
   int door1 = 6;                // PWM pin
   boolean door1Open = false;
   //Servo door1;
 
   //int spare1Pin = 4;	// Spare bit for future use
   //boolean spare1On = OFF;
 
   int door2 = 9;                // PWM pin
   boolean door2Open = false;
   //Servo door2;
 
   int door3 = 10;                // PWM pin
   boolean door3Open = false;
   //Servo door3;
 
   int door4 = 11;                // PWM pin
   boolean door4Open = false;
   //Servo door4;
 
   //byte switchStates = B00000000;		// 8 bits keeping track of switch states
         					// 0 = OFF, 1 = ON
   // Setup output pins for local status leds
   int RFLink = 7;		// Blue LED, on if associated to Xbee network
   int RXLED = 8;		// Yellow LED, On if Xbee-RX
   int TXLED = 12;		// Yellow LED, On if Xbee-TX
   int ERRLED = 13;	// Red LED, On if some sort of error    occurs

//---------------------------------------------
// Setup()
// Runs once after powering on the board
//---------------------------------------------
void setup() {
   Serial.begin(9600);                      // Enable serial communication
   // Setup output pins for actuators
   // All doors default closed, lights and pump default off.
   // Is it possible to connect LED in circuit to output pins? 
   // That way it is possible to monitor outputs without extra pins for the LED's
   pinMode(lightsPin, OUTPUT);
   pinMode(pumpPin, OUTPUT);
   
   // Setup output pins for local status leds
   pinMode(RFLink, OUTPUT);
   pinMode(RXLED, OUTPUT);
   pinMode(TXLED, OUTPUT);
   pinMode(ERRLED, OUTPUT);
   
   if (debugging) {
     digitalWrite(ERRLED, HIGH);
   }
   
   // TODO: Obtain accurate time from gateway (via NTP) or DCF
   //establish start time
   start_time = now();
   seconds_elapsed_total = 0;
}
//---------------------------------------------

//---------------------------------------------
// Loop()
// Loops time after time, after finishing setup()
//---------------------------------------------
void loop() {
// Notify user that the debugging mode is on!
if (debugging) {
   logMessage("!!! DEBUGGING ENABLED, RF DISABLED !!!", true);
   logMessage("", true);
   digitalWrite(ERRLED, HIGH);
}
   
// Get sensor readings
moisture_val = map(analogRead(moistSensorPin),0,1023,0,999);
light_val = map(analogRead(lightSensorPin),0,1023,999,0);
temp_val = getTempInC(tempSensorPin);			 

//Output debug info
logMessage("+---------- SENSOR READINGS ----------+", true);
logMessage("Soil moisture: ", false);
logMessage(moisture_val, true);
logMessage("Ambient Light: ", false);
logMessage(light_val, true);
logMessage("Temperature: ", false);
logMessage(temp_val, true);
logMessage("+-------- END SENSOR READINGS --------+", true);
logMessage("", true); // Add extra white line in logging


// ***************** Moisture level control ******************
// Pump is switched on if needed and every new loop, it is evaluated if the pump
// needs to on or off. 
// TODO: Maybe a hysteresis is required to prevent jittering, but not implemented until tests are done
// it is expected that the soil does not get wet or dry up soo quickly.
logMessage("+---------- SOIL MOISTURE ------------+", true);
if (moisture_val < CFGTargetMoistLevel)	{ 			// Soil too dry 
      digitalWrite(pumpPin, LOW);			        // Switch pump on
      delay(1000);						// Wait a second to allow switch to happen
      pumpOn = true;	
      logMessage("Pump switched ON", true);		
   } else {                                                       // Soil is OK (or too wet), pump needs to be off
      digitalWrite(pumpPin, HIGH);			        // Switch pump off
      delay(1000);						// Wait a second to allow switch to happen
      pumpOn = false;	                                        // Update state
      logMessage("Pump switched OFF", true);
   }  
logMessage("Pump ON: ", false);
logMessage((bool)pumpOn, true);
logMessage("+--------------------------------------+", true);

// ***************** ********************* ******************

// ****************** Light level control *******************
//update time, and increment seconds_light if the lights are on
logMessage("+---------- LIGHT CONTROL ------------+", true);
seconds_for_this_cycle = now() - seconds_elapsed_total; // How much time in this program cycle
seconds_elapsed_total = now() - start_time;		 // Total time the program is running
if (light_val > CFGDayLightLevel) {				 // There is enough light
   seconds_light = seconds_light + seconds_for_this_cycle;	 // Update the counter that keeps track of the amount light received
   digitalWrite(lightsPin, HIGH);			         // If it was cloudy, lights may be on, switch them off again
   delay(1000);							 // Wait a second to allow switch to happen
   lightOn = false;
   logMessage("Ambient light level above daylightlevel.", true);
   logMessage("Lights are now OFF.", true);
}

//How much of the time since the program is running, has there been enough light?
proportion_lit = seconds_light/seconds_elapsed_total;
logMessage("seconds_elapsed_total: ", false);
logMessage(seconds_elapsed_total, true);
logMessage("seconds_light: ", false);
logMessage(seconds_light, true);
logMessage("start_time: ", false);
//logMessage(start_time, true);
if (debugging) {
Serial.println(start_time);
}
logMessage("proportion_lit: ", false);
logMessage(proportion_lit, true);
logMessage("proportion_to_light: ", false);
logMessage(proportion_to_light, true);

//turn off lights if proportion_lit>proportion_to_light
if (proportion_lit > proportion_to_light) {
   digitalWrite(lightsPin, HIGH);
   delay(1000);							 // Wait a second to allow switch to happen
   lightOn = false;
   logMessage("Enough light received.", true);
   logMessage("Lights are now OFF.", true);  
}

//If there is not enough light and the amount of light received is less than desired, switch lights on
if ((light_val < CFGDayLightLevel) and (proportion_lit < proportion_to_light)) {
      digitalWrite(lightsPin, LOW);
      delay(1000);						// Wait a second to allow switch to happen
      lightOn = true;
      logMessage("Light level below daylight threshold and not enough light received yet", true);
      logMessage("Lights are now ON.", true);  
}
logMessage("Lights ON: ", false);
logMessage((bool)lightOn, true);
logMessage("+--------------------------------------+", true);
logMessage("", true);

// ***************** ********************* ******************

// ****************** Temperature control *******************
// Temperature control is done with a hysteresis:
// Desired temperature - hysteresis = Close all doors
// Desired temperature + hysteresis = Open 2 doors
// Desired temperature + 2*hysteresis = Open all 4 doors
// Temperature within low and high hysteresis, do nothing
logMessage("+---------- TEMPERATURE CONTROL ------------+", true);
if ( temp_val < CFGMinTemp) {		// It is too cold, close the doors!
   // TODO: Close Door1, Door2, Door3, Door4
   closeDoor(door1);
   closeDoor(door2);
   closeDoor(door3);
   closeDoor(door4);
   door1Open = false;
   door2Open = false;
   door3Open = false;
   door4Open = false;   
   logMessage("Temp below minimum, closing all doors", true);
   // TODO: Send "too cold" temperature alarm message to internet gateway
} else {
   
   if (temp_val > CFGMaxTemp) {	        // It's gettin hot in herre, open 2 doors!
      if ( temp_val > CFGAlarmTemp) { // It's now too hot, open all doors
         // TODO: Open Door1, Door2, Door3, Door4   
         openDoor(door1);
         openDoor(door2);
         openDoor(door3);
         openDoor(door4);
         door1Open = true;
         door2Open = true;
         door3Open = true;
         door4Open = true;  
         logMessage("Temperature alarm, opening all doors", true);
         // TODO: Send "too hot" temperature alarm message to internet gateway
      } else {
         // TODO: Open Door1, Door2
         // TODO: Close Door3, Door4
        openDoor(door1);
        openDoor(door2);
        closeDoor(door3);
        closeDoor(door4);
        door1Open = true;
        door2Open = true;
        door3Open = false;
        door4Open = false;  
        logMessage("Temperature high, doors 1 and 2 open", true);
         // TODO: If temperature alarm was raised, lower it
      }
   } 
}
logMessage("Door1 Open: ", false);
logMessage((bool)door1Open, true);
logMessage("Door2 Open: ", false);
logMessage((bool)door2Open, true);
logMessage("Door3 Open: ", false);
logMessage((bool)door3Open, true);
logMessage("Door4 Open: ", false);
logMessage((bool)door4Open, true);
logMessage("+--------------------------------------+", true);
logMessage("", true);

// ***************** ********************* ******************

// ******************** Logging control *********************
// Check against logInterval to see if it is time to send the 
// results to the receiver unit
if (millis() - previousLog > logInterval) {
   previousLog = millis();
   SendLogData();
}
// ***************** ********************* ******************

// Wait 10 seconds. This way, the system uses less power.
delay(10000);		

// Now would be a good time to show some debug data

}

//---------------------------------------------
// getTempInC()
// This function reads the value from the temperature sensor
// (TMP36) and first converts the value into voltage,
// then convert voltage into a temperature in C.
//---------------------------------------------
float getTempInC(int tempSensorPin) {
   // To eliminate jitter or strange readings, lets smooth out the number
   // by averaging 10 readings taken in rapid succession.
   int averageReading = 0;
   int noOfReadings = 10;
   for (int i = 0; i < noOfReadings; i++) {
      averageReading += analogRead(tempSensorPin);
   }
   
   averageReading = (averageReading / (noOfReadings));  // Average the readings
   
   float voltageOnPin = averageReading * .004882814;    // convert reading to voltage (between 0 - +5V)
   return (voltageOnPin - 0.5) * 100;                   // convert voltage to Celsius
}

//---------------------------------------------
// SendLogData()
// This function is responsible for reporting the sensor values
// and states of the actuators via the XBee to a gateway unit.
//---------------------------------------------
void SendLogData() {
String logDataString = "$";
logDataString += DeviceName;
logDataString += ",";

int wholeDegrees = temp_val;         // temp_val is a float, with 2 decimals. Multiply by 10 and put it in an int, means losing the last decimal
int decimalDegrees = (temp_val * 100) - (wholeDegrees * 100);             
logDataString += wholeDegrees;       // add whole degrees
logDataString += ".";                // decimal point
logDataString += abs(decimalDegrees);     // and fractional degrees. 17-12-2010: If temperature is negative, the minus sign is removed from the decimals
logDataString += ",";
logDataString += light_val;          // ambientlight value
logDataString += ",";
logDataString += moisture_val;       // moisture value
logDataString += ",";
logDataString += (int)door1Open;
logDataString += ",";
logDataString += (int)door2Open;
logDataString += ",";
logDataString += (int)door3Open;
logDataString += ",";
logDataString += (int)door4Open;
logDataString += ",";
logDataString += (int)lightOn;
logDataString += ",";
logDataString += (int)pumpOn;
logDataString += ",0.";
logDataString += (int)(proportion_lit*100);
logDataString += "#";
int checkSum = logDataString.length();
logDataString += checkSum;

logMessage("RF Datastring : ", false);
logMessage(logDataString, true);

for (int i = 0; i < logDataString.length(); i++) {
   payload[i] = logDataString.charAt(i);
}
logMessage("Payload: [", false);

if (debugging) {
   for (int i = 0; i < logDataString.length(); i++) {
      Serial.print(payload[i]);
    }
   Serial.println("]");
}

if (!debugging) {
  xbee.send(zbTx);
  flashLed(TXLED, 5, 100);
} else {
   logMessage("Debugging enabled, Xbee communication disabled!", true);
   // flash TX indicator
}

if (!debugging) {
   // after sending a tx request, we expect a status response
   // wait up to half second for the status response
   if (xbee.readPacket(500)) {
       // got a response!
       // flash RX indicator
       flashLed(RXLED, 5, 100);
       // should be a znet tx status            	
       if (xbee.getResponse().getApiId() == ZB_TX_STATUS_RESPONSE) {
          xbee.getResponse().getZBTxStatusResponse(txStatus);
    		
          // get the delivery status, the fifth byte
          if (txStatus.getDeliveryStatus() == SUCCESS) {
             // success.  time to celebrate
             flashLed(RFLink, 5, 100);
             } else {
             // the remote XBee did not receive our packet. is it powered on?
             flashLed(ERRLED, 5, 100);
             }
           }      
       } else {
         // local XBee did not provide a timely TX Status Response -- should not happen
         flashLed(ERRLED, 5, 100);
       }
   }
}

//---------------------------------------------
// flashLed(int pin, int times, int wait)
// This function flashes a LED on [pin], [times] times with [wait] ms between flashes
//---------------------------------------------
void flashLed(int pin, int times, int wait) {
    for (int i = 0; i < times; i++) {
      digitalWrite(pin, HIGH);
      delay(wait);
      digitalWrite(pin, LOW);
      
      if (i + 1 < times) {
        delay(wait);
      }
    }
}

//---------------------------------------------
// openDoor(Servo doorServo)
// This function moves a servo to the open position. 
//---------------------------------------------
void openDoor(int doorServoPin) {
    digitalWrite(doorServoPin, HIGH);
    // Line above used for debugging while only LED is connected
}

//---------------------------------------------
// closeDoor(Servo doorServo)
// This function moves a servo to the close position. 
//---------------------------------------------
void closeDoor(int doorServoPin) {
    digitalWrite(doorServoPin, LOW);
    // Line above used for debugging while only LED is connected
}

//---------------------------------------------
// logMessage(String logMessage)
// This function checks if the global boolean 'debugging' is true
// if so, it prints the logmessage. 
// Params: 
// String logMessage - Contains the text to print to serial
// boolean NLCR - Do or do not add NewLine CarriageReturn after the logmessage
//---------------------------------------------
void logMessage(String logMessage, boolean NLCR) {
    if (debugging) {
       if (NLCR) {                      // Add NewLine Carriage Return at the end 
          Serial.println(logMessage);
       } else {
          Serial.print(logMessage);    // Do not add NL and CR at the end 
       }
    }
}

//---------------------------------------------
// void logMessage(float logFloat, boolean NLCR)
// This function checks if the global boolean 'debugging' is true
// if so, it prints the float value to Serial output. 
// Params: 
// float logFloat - Contains the float to print to serial
// boolean NLCR - Do or do not add NewLine CarriageReturn after the logmessage
//---------------------------------------------
void logMessage(float logFloat, boolean NLCR) {
    if (debugging) {
       if (NLCR) {                      // Add NewLine Carriage Return at the end 
          Serial.println(logFloat);
       } else {
          Serial.print(logFloat);    // Do not add NL and CR at the end 
       }
    }
}

//---------------------------------------------
// void logMessage(int logInt, boolean NLCR)
// This function checks if the global boolean 'debugging' is true
// if so, it prints the float value to Serial output. 
// Params: 
// float logFloat - Contains the float to print to serial
// boolean NLCR - Do or do not add NewLine CarriageReturn after the logmessage
//---------------------------------------------
void logMessage(int logInt, boolean NLCR) {
    if (debugging) {
       if (NLCR) {                      // Add NewLine Carriage Return at the end 
          Serial.println(logInt);
       } else {
          Serial.print(logInt);    // Do not add NL and CR at the end 
       }
    }
}

//---------------------------------------------
// void logMessage(char logChar, boolean NLCR)
// This function checks if the global boolean 'debugging' is true
// if so, it prints the float value to Serial output. 
// Params: 
// float logFloat - Contains the float to print to serial
// boolean NLCR - Do or do not add NewLine CarriageReturn after the logmessage
//---------------------------------------------
void logMessage(char logChar, boolean NLCR) {
    if (debugging) {
       if (NLCR) {                      // Add NewLine Carriage Return at the end 
          Serial.println(logChar);
       } else {
          Serial.print(logChar);    // Do not add NL and CR at the end 
       }
    }
}
