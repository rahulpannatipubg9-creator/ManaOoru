# MANA OORU: Godavarikhani & Ramagundam Public Source Research Report
**Project Context:** MANA OORU Open-World Environment  
**Research Date:** 31 October 2026  
**Projection Origin:** Godavarikhani Chowrastha (Lat: 18.751925° N, Lon: 79.513352° E), Playable Radius: 3,000 m  
**Scope:** Public sector and open authoritative sources for geography, transport, industry, culture, and environmental design.

---

## 1. Executive Summary & Source Cross-Check

This research synthesizes verified public information from official Telangana State Government portals, Ramagundam Municipal Corporation, Peddapalli District Administration, National Thermal Power Corporation (NTPC), The Singareni Collieries Company Limited (SCCL), TGSRTC, and OpenStreetMap (OSM) / Overture Maps.

### Official Source Verification Matrix

| Official Entity / Portal | URL | Access Date | Supported Claims & Verified Context | Reuse & License Terms |
|---|---|---|---|---|
| **Ramagundam Municipal Corporation** | `https://ramagundamcorporation.telangana.gov.in/pages/about-us` | 31 Oct 2026 | Known as "City of Energy" & "Coal City"; area 104.34 km²; urban body covering Godavarikhani, Ramagundam, and coal belt; anchors SCCL, RFCL, and NTPC. | Government of Telangana public domain / NDSAP. Factual civic records; fair use. |
| **Peddapalli District Administration (History & Profile)** | `https://peddapalli.telangana.gov.in/history/` | 31 Oct 2026 | Formed 2016 from Karimnagar district; historical heritage (Dhulikatta Buddhist Stupa, Ramagiri Fort); regional transport hub; RTA code TG-22. | Government of Telangana public domain. Factual historical data. |
| **Peddapalli District Administration (Transport)** | `https://peddapalli.telangana.gov.in/how-to-reach/` | 31 Oct 2026 | Grand Trunk rail connectivity via Peddapalli & Ramagundam; Rajiv Rahadari (SH-1) highway corridor from Hyderabad; local Basant Nagar airstrip. | Government of Telangana public domain. Factual transport data. |
| **NTPC Limited (Ramagundam Project Disclosures)** | `https://ntpc.co.in/ramagundam` | 31 Oct 2026 | Ramagundam Super Thermal Power Station (2,600 MW: 3×200 MW + 4×500 MW across 3 stages); 100 MW floating solar PV on 500-acre reservoir; Jyothi Nagar township (PIN 505215). | Corporate disclosure / factual operational data. Trademarks (NTPC, BHEL) proprietary; use descriptive names in game. |
| **Peddapalli District Fisheries & Co-operative** | `https://peddapalli.telangana.gov.in/co-operative/` | 31 Oct 2026 | Inland fisheries societies under District Fisheries Officer & Telangana State Fishermen Cooperative Societies Federation; Godavari river fishing leases; Godavari Pushkar Ghats. | Government of Telangana public domain. |
| **Government Medical College & General Hospital Ramagundam** | `https://gmcramagundam.in` | 31 Oct 2026 | Established beside Government Degree College, Malkapur / Sharada Nagar (PIN 505209); incorporates/upgrades the Singareni Area Hospital / Govt Area Hospital into GMC teaching hospital. | Government educational portal; factual facility details. |
| **The Singareni Collieries Company Limited (SCCL)** | `https://scclmines.com` | 31 Oct 2026 | Ramagundam coal belt divided into RG-1, RG-2, RG-3 areas; GDK-1 & 3, GDK-5, GDK-8, GDK-11 inclines; Ramagundam Opencast Projects (RG OC-III, Medipalli OCP); feeder line to NTPC. | Public Sector Undertaking operational data. Public technical records. |
| **OpenStreetMap & Overture Maps Data** | `data/osm/godavarikhani_core.json`, `data/places/godavarikhani_places.json` | 24–27 Oct 2026 | Mapped road network, Chowrastha roundabout (way 818565606), Godavari road bridge (way 758926574), TGSRTC depot/bus station, local shops & amenities. | ODbL 1.0 (OSM attribution required: "© OpenStreetMap contributors") & CDLA-Permissive-2.0. |

---

## 2. In-Depth Investigations: 'NTPC Road' & 'Taj Restaurant'

### A. Investigation of 'Taj Restaurant'
* **Finding:** **Taj Family Restaurant is BOTH an authentic physical landmark in Godavarikhani AND a common regional culinary branding.**
* **Local Identity & Location:**
  - **Primary Physical Establishment:** "Taj Family Restaurant & Fast Foods" is an established, high-profile dining spot located on the **Main Road / Markandeya Colony / Laxmi Nagar / Kalyan Nagar stretch (near ICICI Bank)**, Godavarikhani, PIN 505211.
  - It is an active local landmark famous for Hyderabadi/Telangana Dum Biryani, chicken fry piece biryani, and rumali roti, operating both dine-in family lounge service and app delivery (Swiggy/Zomato).
  - In OpenStreetMap: Located at `osm/node/6976908414` (`amenity=restaurant`, name=`Taj family restaurant`) at coordinates **(18.7548204° N, 79.5052200° E)**, which places it approximately **850 meters west-northwest of Chowrastha**, well inside the 3,000 m playable area.
* **Secondary Dataset Entry:**
  - Overture Maps records another entry: `catalog/place/c01303ff4df5c101` (`Taj Family restaurant`) at **(18.7621239° N, 79.4824942° E)**, address "No D2/57, 8B, Godavarikhani". This corresponds to the 8-Incline Colony / 8B mining colony periphery (~3.4 km west-northwest, just outside the 3 km circle).
* **Environment Recommendation:**
  - Anchor the main commercial restaurant as **Verified Geography** along the Main Road/Laxmi Nagar strip using the OSM node `6976908414` location.
  - Model it with authentic local Telangana town signage: multi-color LED/flex board, "Taj Family Restaurant & Biryani Point", glass entrance, ground-floor takeaway counter, and roadside motorcycle parking.

### B. Verification of 'NTPC Road' (Geometry & Alignment)
* **Finding:** **"NTPC Road" is the primary east-west arterial corridor connecting Godavarikhani town center to the NTPC Ramagundam industrial township (Jyothi Nagar).**
* **Geometry and Alignment:**
  1. **Eastern Origin (Godavarikhani):** Originates from Godavarikhani Chowrastha / Main Road (18.751925° N, 79.513352° E), extending west past L.B. Nagar, 8-Incline Colony turnoffs, and Markandeya Colony.
  2. **Mid-Corridor Junctions:** Passes through the **FCI X-Roads (Fertilizer Corporation / RFCL intersection)** and colliery access points.
  3. **Township Segment:** Transitions into the dual-carriageway tree-lined corridor tagged in OSM as `township main road` (OSM ways `132220842`, `818565673`, `1296557287`) running from **79.483° E to 79.489° E** and **18.756° N to 18.761° N**.
  4. **Western Terminus:** Reaches the NTPC Township Main Gate (Jyothi Nagar) and security checkpoints leading to the Super Thermal Power Station and Kendriya Vidyalaya.
* **Relationship to Rajiv Rahadari (SH-1):**
  - Rajiv Rahadari (Hyderabad–Karimnagar–Ramagundam–Mancherial State Highway 1) approaches from the south (Basant Nagar/Peddapalli) toward Godavarikhani and crosses the Godavari River to Mancherial.
  - NTPC Road serves as the dedicated lateral connector linking Rajiv Rahadari and Godavarikhani town with Jyothi Nagar and the power plant complex.
* **Environment Recommendation:**
  - **Verified Geometry:** Inside the 3 km playable circle (from Chowrastha to 79.485° E), use the real OSM alignment (secondary/tertiary roads and the eastern end of `township main road`).
  - **Approximate Adaptation:** Because the full NTPC power plant sits ~5.5 km west, compress the distance along NTPC Road so players can drive seamlessly from Godavarikhani Market, through the green township entrance gates, directly into Jyothi Nagar.

---

## 3. Environment Decision Classifications

To ensure transparency between real-world cartography, creative adaptation, and game requirements, every environment asset and system is classified below:

| Environment Feature | Classification | Ground Truth / Technical Evidence | Adaptation & In-Game Rationale |
|---|---|---|---|
| **Godavarikhani Chowrastha** | **Verified Geography** | OSM way `818565606` & node `3384152837` at `(79.513352, 18.751925)`. | Game world origin `(0, 0, 0)`. Exact roundabout geometry with 4 major arms. |
| **Godavari River Road Bridge** | **Verified Geography** | OSM ways `758926574`, `817699110` (`hw=trunk`, `bridge=yes`) at `(79.5116–79.5170, 18.7710–18.7755)`. | Located ~2.1 km north of Chowrastha (inside 3 km radius). High-level concrete pier bridge spanning dry riverbed/sand and active channels. |
| **Godavari Pushkar Ghat & Kalyan Nagar Riverfront** | **Verified Geography** | District records, Kalyan Nagar ghat road, Godavari riverbed. | Bathing steps, river shrines, sand expanse, fishermen boat moorings. |
| **TGSRTC Godavarikhani Bus Station & Depot** | **Verified Geography** | OSM node `13707521637` and depot way `279050788` at `(79.5082894, 18.7601255)`. | Bus bays, enquiry booth, Palle Velugu / Express buses, passenger shelter. |
| **Main Commercial Streets (Laxmi Nagar, Markandeya Colony)** | **Verified Geography** | OSM roads and Overture address records; verified shop clusters. | Dense multi-story commercial shop fronts, chai stalls, mobile shops, pharmacies. |
| **Taj Family Restaurant** | **Verified Geography** | OSM node `6976908414` at `(18.7548204, 79.5052200)`. | Specific commercial biryani and family restaurant landmark along the Main Road. |
| **New Ashok Theatre** | **Verified Geography** | OSM way `331357115` at `(79.51507258, 18.7542867)`. | Single-screen cinema hall with movie cutouts/posters ~350 m northeast of Chowrastha. |
| **Singareni Area Hospital / GMC Ramagundam** | **Verified Geography / Clarified** | GMC Ramagundam site at Malkapur/Sharada Nagar; OSM nodes `6542777509` & `11937607118`. | Resolution of dual OSM pins: Area Hospital is now integrated into GMC Ramagundam teaching campus. Model as large civic hospital complex. |
| **Jawaharlal Nehru Stadium (SCCL)** | **Verified Geography** | SCCL sports complex in Godavarikhani (PIN 505209). | Multi-purpose sports stadium with cricket pitch, athletic track, and pavilion. |
| **NTPC Jyothi Nagar Township** | **Approximate Adaptation** | Physically located ~4–6 km west (Jyothi Nagar township, PO 505215). | Spatially compressed: bring the iconic landscaped township gate, wide boulevards, quarters, and Mahatma Gandhi Stadium to the western boundary (~2.5–3 km from origin). |
| **NTPC Thermal Power Plant (Cooling Towers & Chimneys)** | **Approximate Adaptation / Vista** | Coordinates `(18.755° N, 79.456° E)` (5.8 km west). | Render cooling towers and towering chimneys as a dramatic background skyline (3D skybox / horizon vista) with steam plumes visible across the map. |
| **NTPC Floating Solar Project** | **Approximate Adaptation** | 100 MW floating solar PV on 500-acre reservoir in NTPC cooling pond. | Feature a visible water reservoir with floating HDPE solar arrays on the western/north-western approach. |
| **Ramagundam Railway Station (RDM)** | **Approximate Adaptation / Fast-Travel Hub** | Grand Trunk route `(18.760° N, 79.430° E)` (~8.7 km west of Chowrastha). | Physically outside the 3 km circle. Either represent via a compressed rail siding/spur or as a transport transition point / mission destination connected via Rajiv Rahadari. |
| **SCCL Coal Mines (Inclines & Opencast)** | **Verified Geography & Adaptation** | RG-1 & RG-2 areas; GDK-11, GDK-8 Incline Colony, Medipalli OCP. | Headframes, conveyor galleries over roads, pithead offices, coal dust roads, coal hopper loading sidings on southern/eastern perimeters. |
| **District Cooperative Fishing Vessels** | **Verified Geography / Gameplay Detail** | Peddapalli Fisheries Dept, Godavari riverbed. | Traditional wooden country crafts (*naavalu*), circular coracles, nylon nets drying on poles, morning fish auction market along the river edge. |
| **Street Ambience & Props** | **Authentic Cultural Detail** | Local Telangana coal belt culture. | Blue tarpaulin shop awnings, auto-rickshaws (7-seater Ape/Vikram and 3-seater Bajaj), miner scooters with helmets, Telugu safety slogans, roadside tiffin stalls. |

---

## 4. Actionable District Guidance for MANA OORU

### District 1: Godavarikhani Commercial & Mining Market
* **Atmosphere:** Bustling, dusty, energetic Telangana industrial-commercial crossroads.
* **Core Landmarks:**
  - **Chowrastha Roundabout:** Central island with Dr. B.R. Ambedkar / Mahatma Gandhi statue, traffic police post, political flex banners, high-mast floodlight.
  - **TGSRTC Bus Station & Depot:** Active transit hub featuring green-and-white *Palle Velugu* rural buses, blue-and-white *Express* buses, ticket counters, tea stalls, and auto stands.
  - **Main Road & Laxmi Nagar Strip:** Two- to three-story mixed commercial buildings with ground-floor shutters: mobile recharge, medical stores, gold loan offices, textile shops, Sweet Magic / Arjun Sweet House, and electronics.
  - **Taj Family Restaurant:** Landmark dining building on Main Road with recognizable Telugu/English signboard, takeaway counter, and parking.
  - **New Ashok Theatre:** Traditional single-screen theatre with massive hand-painted/flex Telugu cinema hero banners, ticket counter grille, and cycle stand.
* **Audio & Visual Polish:**
  - Traffic hum: Two-stroke autorickshaws, horn honks, TGSRTC bus air-brakes, Telugu FM radio songs from tea stalls, evening call to prayer / temple bells.

### District 2: NTPC / Jyothi Nagar Township
* **Atmosphere:** Orderly, quiet, leafy, institutional contrast to the gritty coal town.
* **Core Landmarks:**
  - **Township Main Gate & Security Checkpoint:** Grand arched entrance with NTPC corporate blue/green signage, security barriers, and visitor booth.
  - **Avenue Roads:** Wide dual-carriageway roads (`township main road`) lined with gulmohar, neem, and royal palm trees, clean concrete curbstones, and pedestrian footpaths.
  - **Institutional Facilities:** Kendriya Vidyalaya / St. Claire High School campus, post office, community center, and **Mahatma Gandhi Stadium**.
  - **NTPC Reservoir & Floating Solar Vista:** Glimpse of the balancing reservoir with rows of floating solar panels reflecting the sky.
  - **Power Plant Horizon:** Massive natural-draft hyperbolic cooling towers emitting continuous white steam plumes, flanked by tall multi-flue chimneys with red/white aviation bands.

### District 3: Ramagundam Railway Area
* **Atmosphere:** Heavy rail artery connecting South and North India, freight-heavy coal transport.
* **Core Landmarks:**
  - **Station Building:** Characteristic South Central Railway (SCR) design, painted in Indian Railways maroon/cream or terracotta/white with bilingual Telugu, Hindi, and English station boards ("రామగుండం / रामगुंडम / RAMAGUNDAM").
  - **Platform & Overhead Footbridge:** Covered high-level platforms with cement benches, water coolers, wheel-mounted tea/book stalls, and high steel lattice pedestrian footbridge.
  - **Goods Yard & Coal Rakes:** Multi-track marshalling siding with WAG-9 / WDG-4 electric and diesel freight locomotives hauling long rakes of *BOXN* coal wagons toward NTPC and national grids.
  - **Station Approach:** Auto-rickshaw stand, tea shops, budget lodges, cycle stands, and parcel delivery sheds.

### District 4: Mining Residential Colonies (SCCL)
* **Atmosphere:** Distinctive company-town planned worker housing steeped in coal mining heritage.
* **Core Landmarks:**
  - **SCCL Quarters:** Grid layouts of Type-A, Type-B single/double-room worker quarters featuring tiled sloping roofs or flat terraces, whitewashed walls with blue basebands, stenciled house numbers, small front courtyards, and tulasi pots.
  - **Mine Incline Entrances (e.g., GDK-8 / GDK-11):** Concrete incline portal dipping into the ground, steel headgear frame with rotating sheave wheels, cable haulage engines, and pithead bathhouse.
  - **Mine Infrastructure:** Overhead enclosed conveyor galleries crossing over the roadway, time office with punch clocks, lamp room where miners deposit battery packs, and siren tower (sounding shift changes at 6 AM, 2 PM, 10 PM).
  - **Community Amenities:** Workers' recreation club, Singareni workers' union office flags (AITUC / INTUC / Telangana Boggu Gani Karmika Sangham), and Jawaharlal Nehru Stadium.

### District 5: Godavari Waterfront & Bridge Fishing Community
* **Atmosphere:** Natural, serene, expansive river basin contrasting with industrial steel and coal.
* **Core Landmarks:**
  - **Godavari Road Bridge:** Long multi-span prestressed concrete girder bridge carrying Rajiv Rahadari / Mancherial traffic high above the riverbed, with concrete crash barriers and light poles.
  - **Riverbed Topography:** Broad sandy floodplains with seasonal river channels, gravel sandbars, and rocky outcrops.
  - **Godavari Pushkar Ghat (Kalyan Nagar):** Broad stone/concrete bathing ghat steps descending to the water, small Shiva / Hanuman shrines, changing rooms, and riverbank flagpoles.
  - **Fishermen Cooperative Moorings:**
    - Clustered traditional wooden long-boats (*naavalu*) anchored with ropes to wooden stakes.
    - Woven circular bamboo-and-tarp coracles (*teppalu*) resting inverted on the sandbank.
    - Blue and white nylon gill nets draped over bamboo racks to dry in the sun.
    - Makeshift thatched sheds of local fishermen cooperative members, with weighing scales, plastic crates, and fresh catch (Rohu, Katla, Murrel/Koramenu).

---

## 5. Summary Table of Verified Data Points for Game Developers

| Attribute | Game Value / Specification | Real-World Public Evidence |
|---|---|---|
| **World Origin** | `(0, 0, 0)` at Chowrastha | 18.751925° N, 79.513352° E (OSM roundabout `818565606`) |
| **Playable Radius** | 3,000 meters | Covers Godavarikhani core, riverfront, bridge, colonies, and township fringe |
| **River Location** | +Z = -2,100 m (North) | Godavari River southern bank at 18.771° N |
| **Primary Highway** | Rajiv Rahadari (SH-1) | Links Hyderabad – Karimnagar – Godavarikhani – Mancherial |
| **Secondary East-West Spine** | NTPC Road | Connects Chowrastha west to FCI X-Roads & Jyothi Nagar |
| **Bus Transit Hub** | TGSRTC Godavarikhani Depot | 18.7601° N, 79.5083° E (Opposite Traffic PS) |
| **Railway Hub** | Ramagundam (RDM) | Grand Trunk Line, 18.760° N, 79.430° E (SCR Division) |
| **Power Infrastructure** | NTPC 2,600 MW + 100 MW Solar | 18.755° N, 79.456° E (Commissioned 1983–2022) |
| **Mining Operators** | SCCL RG-1, RG-2, RG-3 | GDK Inclines (1, 3, 5, 8, 11), Medipalli OCP, RG OC-III |
| **Primary Hospital** | GMC Ramagundam / Area Hospital | Malkapur / Sharada Nagar (Beside Govt Degree College) |
| **Signature Restaurant** | Taj Family Restaurant | 18.7548° N, 79.5052° E (Main Road / Markandeya Colony) |
| **Primary Cinema** | New Ashok Theatre | 18.7543° N, 79.5151° E (Hanuman Nagar / Chowrastha North) |
| **Local Sports** | JN Stadium (SCCL) & MG Stadium (NTPC) | Godavarikhani (SCCL) & Jyothi Nagar (NTPC) |
