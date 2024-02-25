#define SHOCK_PIN 2
#define INTENSITY_UP_PIN 3
#define INTENSITY_DOWN_PIN 4


int old_intensity = 1;
int click_delay = 50;

void setup() {
  // Initialize serial communication:
  Serial.begin(9600);
  // Set pins as output
  
  pinMode(SHOCK_PIN, OUTPUT);
  pinMode(INTENSITY_UP_PIN, OUTPUT);
  pinMode(INTENSITY_DOWN_PIN, OUTPUT);
  digitalWrite(SHOCK_PIN, HIGH);
  digitalWrite(INTENSITY_UP_PIN, HIGH);
  digitalWrite(INTENSITY_DOWN_PIN, HIGH);
}

void separateIntegers(const char* inputString, int& sValue, int& tValue, int& iValue) {
    // Parsing the string
    sscanf(inputString, "s%d t%d i%d", &sValue, &tValue, &iValue);
}
void shock(int wait) {
  // Set pin high
  //Serial.println("Shock called");
  //Serial.println(wait, DEC);
  digitalWrite(SHOCK_PIN, LOW);
  // Wait for intensity milliseconds
  delay(wait);
  // Set pin low
  digitalWrite(SHOCK_PIN, HIGH);
  //Serial.println("Shock finished.");
}

void intensity(int intensity) {
  // Set pin high
  int delta = intensity - old_intensity;
  //Serial.println("Intensity called");
  //Serial.println(delta, DEC);
  if (delta==0){
    return;
  }
  else if (delta > 0){
    //Serial.println("Upping intensity");
    //Serial.println(delta, DEC);
    for(int i = 0; i<delta; i++){
      delay(click_delay);
      digitalWrite(INTENSITY_UP_PIN, LOW);
      delay(click_delay); // You can modify this if needed
      // Set pin low
      digitalWrite(INTENSITY_UP_PIN, HIGH);
    }
  }
  else{
    //Serial.println("Decreasing intensity");
    //Serial.println(delta, DEC);
    for(int i = 0; i<delta*-1; i++){
      delay(click_delay);
      digitalWrite(INTENSITY_DOWN_PIN, LOW);
      delay(click_delay); // You can modify this if needed
      // Set pin low
      digitalWrite(INTENSITY_DOWN_PIN, HIGH);
    }
  }
  old_intensity = intensity;
  //Serial.println("Intensity finished.");
  //Serial.println(intensity);
}

void loop() {
  // Check if data is available to read
  int sValue, tValue, iValue;
  if (Serial.available() > 0) {
    // Read the string until newline character ('\n')
    String data = Serial.readStringUntil('\n');
    data.trim(); // Remove any leading/trailing whitespace
    
    // Convert String to char*
    char* inputString = strdup(data.c_str()); // Remember to free memory later
    
    // Now you can use inputString as a char* in your function
    separateIntegers(inputString, sValue, tValue, iValue);
    //Serial.println(inputString);
    //Serial.println(sValue);
    //Serial.println(tValue);
    //Serial.println(iValue);
    // Free the allocated memory for inputString when you're done with it
    free(inputString);
    // Indicate received data
    //Serial.print("Received data: ");
    //Serial.println(data);
    

    if(sValue == 1){
      shock(tValue);
    }
    intensity(iValue);

    // Check if the received string starts with 'shock' or 'intensity'
    
  }
}
