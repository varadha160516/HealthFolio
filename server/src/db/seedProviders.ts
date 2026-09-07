import { v4 as uuid } from 'uuid';
import { db, now } from './db.js';

/**
 * A demo doctor directory spread across several Indian metro areas, so "nearby doctors" has
 * something real to search regardless of which city a tester's phone actually reports as its
 * location. This is NOT a real third-party doctor directory (no such integration exists in this
 * build) — every name, clinic, and coordinate here is invented for demo purposes. A real product
 * would replace this with a live provider-directory data source.
 *
 * Idempotent: checks for a marker clinic before inserting, safe to run on every startup.
 */
export function seedProviderDirectory() {
  // Matches the actual seeded shape ("<clinic name> — <city>") — an earlier version of this
  // check looked for the bare clinic name with no city suffix, which never matched anything and
  // silently re-seeded the whole directory on every single server restart. Caught via a real
  // duplicate-data count, not by inspection — worth remembering when writing the next one of these.
  const marker = db.prepare("SELECT 1 FROM clinics WHERE name LIKE 'Lakeside Multispecialty Clinic %'").get();
  if (marker) return;

  type ClinicSeed = { name: string; city: string; lat: number; lng: number; address: string };
  type DoctorSeed = { name: string; specialty: string; availability: string };

  // Small lat/lng offsets to scatter clinics realistically around each city center rather than
  // stacking them on the exact same point.
  const offset = (base: number, km: number) => base + km / 111; // ~111km per degree of latitude, close enough for demo scatter

  const cities: { name: string; lat: number; lng: number }[] = [
    { name: 'Bengaluru', lat: 12.9716, lng: 77.5946 },
    { name: 'Mumbai', lat: 19.076, lng: 72.8777 },
    { name: 'Delhi', lat: 28.7041, lng: 77.1025 },
    { name: 'Chennai', lat: 13.0827, lng: 80.2707 },
    { name: 'Hyderabad', lat: 17.385, lng: 78.4867 },
    { name: 'Pune', lat: 18.5204, lng: 73.8567 },
  ];

  const clinicNames = ['Lakeside Multispecialty Clinic', 'Greenview Health Centre', 'Northgate Medical Centre', 'Riverside Clinic & Diagnostics'];

  // Each city gets the same specialty spread (at different clinics/doctors) so coverage is
  // consistent no matter which of these cities a tester happens to be near.
  const doctorsPerCity: DoctorSeed[] = [
    { name: 'Dr. Kavita Menon', specialty: 'General Physician', availability: 'Mon-Sat, 9am-1pm & 5pm-8pm' },
    { name: 'Dr. Arjun Nair', specialty: 'Pediatrician', availability: 'Mon-Fri, 10am-6pm' },
    { name: 'Dr. Sunita Verma', specialty: 'Gynecologist / Obstetrician', availability: 'Tue, Thu, Sat, 11am-4pm' },
    { name: 'Dr. Rajeev Iyer', specialty: 'Cardiologist', availability: 'Mon-Wed-Fri, 4pm-8pm' },
    { name: 'Dr. Meera Pillai', specialty: 'Dermatologist', availability: 'Mon-Sat, 10am-2pm' },
    { name: 'Dr. Vikram Das', specialty: 'Dentist', availability: 'Mon-Sat, 9am-7pm' },
    { name: 'Dr. Anjali Kulkarni', specialty: 'ENT Specialist', availability: 'Mon, Wed, Fri, 5pm-8pm' },
    { name: 'Dr. Sanjay Bhatt', specialty: 'Orthopedist', availability: 'Tue-Sun, 6pm-9pm' },
    { name: 'Dr. Priya Desai', specialty: 'Neurologist', availability: 'Mon-Fri, 11am-3pm' },
    { name: 'Dr. Rohit Chawla', specialty: 'Psychiatrist', availability: 'By appointment, Mon-Sat' },
    { name: 'Dr. Lakshmi Raman', specialty: 'Ophthalmologist', availability: 'Mon-Sat, 10am-5pm' },
    { name: 'Dr. Farah Sheikh', specialty: 'Gastroenterologist', availability: 'Mon, Tue, Thu, 4pm-7pm' },
    { name: 'Dr. Naveen Reddy', specialty: 'Endocrinologist', availability: 'Wed, Sat, 10am-1pm' },
    { name: 'Dr. Pooja Agarwal', specialty: 'Dietitian / Nutritionist', availability: 'Mon-Fri, 9am-5pm' },
    { name: 'Dr. Karan Malhotra', specialty: 'Physiotherapist', availability: 'Mon-Sat, 7am-11am & 4pm-8pm' },
    { name: 'Dr. Divya Shenoy', specialty: 'Psychologist / Counselor', availability: 'By appointment' },
  ];

  const insertClinic = db.prepare('INSERT INTO clinics (id, name, address, city, latitude, longitude) VALUES (?, ?, ?, ?, ?, ?)');
  const insertProvider = db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id, availability_note) VALUES (?, ?, ?, ?, ?, ?)');

  const tx = db.transaction(() => {
    for (const city of cities) {
      for (let i = 0; i < doctorsPerCity.length; i++) {
        const doc = doctorsPerCity[i];
        const clinicName = `${clinicNames[i % clinicNames.length]} — ${city.name}`;
        const clinicId = uuid();
        // Scatter within roughly 0-18km of the city center in a rough spiral so distance
        // filtering (20km radius) has a realistic mix of hits and near-misses.
        const km = 1.5 + (i % 8) * 2.2;
        const angle = (i * 47) % 360;
        const lat = offset(city.lat, km * Math.cos((angle * Math.PI) / 180));
        const lng = offset(city.lng, (km * Math.sin((angle * Math.PI) / 180)) / Math.cos((city.lat * Math.PI) / 180));
        insertClinic.run(clinicId, clinicName, `${20 + i} Health District Road`, city.name, lat, lng);
        insertProvider.run(uuid(), 'doctor', doc.name, doc.specialty, clinicId, doc.availability);
      }
    }
  });
  tx();

  console.log(`Seeded demo doctor directory: ${cities.length * doctorsPerCity.length} doctors across ${cities.length} cities (not a real directory — see seedProviders.ts).`);
}

/**
 * A second doctor per specialty per city — the original seed had exactly one, which meant a
 * member searching "Cardiologist" (for example) only ever saw a single option with no real choice.
 * Kept as its own idempotent step (its own marker doctor, checked independently of
 * seedProviderDirectory's) rather than folded into that function, so it can top up an
 * already-seeded database — including this app's own dev database — without needing a fresh start.
 */
export function seedSecondDoctorPerSpecialty() {
  const marker = db.prepare("SELECT 1 FROM providers WHERE name = 'Dr. Ritu Shah'").get();
  if (marker) return;

  // Same specialty list as seedProviderDirectory's doctorsPerCity, one new name each.
  const secondDoctors: { name: string; specialty: string; availability: string }[] = [
    { name: 'Dr. Ritu Shah', specialty: 'General Physician', availability: 'Mon-Fri, 2pm-6pm' },
    { name: 'Dr. Manoj Pillai', specialty: 'Pediatrician', availability: 'Tue-Sat, 9am-1pm' },
    { name: 'Dr. Neha Kapoor', specialty: 'Gynecologist / Obstetrician', availability: 'Mon, Wed, Fri, 10am-2pm' },
    { name: 'Dr. Ashok Subramaniam', specialty: 'Cardiologist', availability: 'Tue, Thu, Sat, 9am-1pm' },
    { name: 'Dr. Ritika Bose', specialty: 'Dermatologist', availability: 'Mon-Fri, 3pm-7pm' },
    { name: 'Dr. Imran Qureshi', specialty: 'Dentist', availability: 'Mon-Sat, 11am-8pm' },
    { name: 'Dr. Swati Joshi', specialty: 'ENT Specialist', availability: 'Tue, Thu, 10am-1pm' },
    { name: 'Dr. Amitabh Ghosh', specialty: 'Orthopedist', availability: 'Mon-Fri, 9am-12pm' },
    { name: 'Dr. Nandini Krishnan', specialty: 'Neurologist', availability: 'Wed, Fri, 2pm-6pm' },
    { name: 'Dr. Vivek Saxena', specialty: 'Psychiatrist', availability: 'By appointment, Tue-Sat' },
    { name: 'Dr. Shalini Rao', specialty: 'Ophthalmologist', availability: 'Mon-Sat, 11am-4pm' },
    { name: 'Dr. Deepak Chandran', specialty: 'Gastroenterologist', availability: 'Wed, Fri, Sat, 5pm-8pm' },
    { name: 'Dr. Aarti Bhalla', specialty: 'Endocrinologist', availability: 'Mon, Thu, 3pm-6pm' },
    { name: 'Dr. Rakesh Thakur', specialty: 'Dietitian / Nutritionist', availability: 'Mon-Sat, 10am-6pm' },
    { name: 'Dr. Simran Kaur', specialty: 'Physiotherapist', availability: 'Mon-Fri, 8am-12pm & 5pm-8pm' },
    { name: 'Dr. Ovais Ahmed', specialty: 'Psychologist / Counselor', availability: 'By appointment' },
  ];

  const cities = db.prepare('SELECT DISTINCT city FROM clinics WHERE city IS NOT NULL').all() as { city: string }[];
  // One clinic per city to attach these to — reuses whichever clinic already exists there rather
  // than inventing new coordinates.
  const clinicForCity = db.prepare('SELECT id FROM clinics WHERE city = ? ORDER BY name LIMIT 1');
  const insertProvider = db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id, availability_note) VALUES (?, ?, ?, ?, ?, ?)');

  const tx = db.transaction(() => {
    for (const { city } of cities) {
      const clinic = clinicForCity.get(city) as { id: string } | undefined;
      if (!clinic) continue;
      for (const doc of secondDoctors) {
        insertProvider.run(uuid(), 'doctor', doc.name, doc.specialty, clinic.id, doc.availability);
      }
    }
  });
  tx();

  console.log(`Seeded a second doctor per specialty per city (${secondDoctors.length} more names × ${cities.length} cities).`);
}
