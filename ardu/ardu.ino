#define SHOCK_PIN 2
#define INTENSITY_UP_PIN 3
#define INTENSITY_DOWN_PIN 4


int old_intensity = 1;

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

void shock(int wait) {
  // Set pin high
  Serial.println("Shock called");
  Serial.println(wait, DEC);
  digitalWrite(SHOCK_PIN, LOW);
  // Wait for intensity milliseconds
  delay(wait);
  // Set pin low
  digitalWrite(SHOCK_PIN, HIGH);
  Serial.println("Shock finished.");
}

void intensity(int intensity) {
  // Set pin high
  int delta = intensity - old_intensity;
  Serial.println("Intensity called");
  Serial.println(delta, DEC);
  if (delta==0){
    return;
  }
  else if (delta > 0){
    Serial.println("Upping intensity");
    Serial.println(delta, DEC);
    for(int i = 0; i<delta; i++){
      delay(30);
      digitalWrite(INTENSITY_UP_PIN, LOW);
      delay(30); // You can modify this if needed
      // Set pin low
      digitalWrite(INTENSITY_UP_PIN, HIGH);
    }
  }
  else{
    Serial.println("Decreasing intensity");
    Serial.println(delta, DEC);
    for(int i = 0; i<delta*-1; i++){
      delay(30);
      digitalWrite(INTENSITY_DOWN_PIN, LOW);
      delay(30); // You can modify this if needed
      // Set pin low
      digitalWrite(INTENSITY_DOWN_PIN, HIGH);
    }
  }
  old_intensity = intensity;
  Serial.println("Intensity finished.");
  Serial.println(intensity);
}

void loop() {
  // Check if data is available to read
  if (Serial.available() > 0) {
    // Read the string until newline character ('\n')
    String data = Serial.readStringUntil('\n');
    // Indicate received data
    Serial.print("Received data: ");
    Serial.println(data);

    // Check if the received string starts with 'shock' or 'intensity'
    if (data.startsWith("shock")) {
      // Extract the intensity value from the string
      int intensityValue = data.substring(5).toInt();
      // Indicate parsed intensity value
      Serial.print("Parsed intensity value: ");
      Serial.println(intensityValue);
      shock(intensityValue);
    } else if (data.startsWith("intensity")) {
      // Extract the intensity value from the string
      int intensityValue = data.substring(9).toInt();
      // Indicate parsed intensity value
      Serial.print("Parsed intensity value: ");
      Serial.println(intensityValue);
      intensity(intensityValue);
    }
  }
}
