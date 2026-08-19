Package ID: H8 · 2026-08-19 · Status: final · Sources verified as of 2026-08-19

## FINDINGS

### OCPI

The Open Charge Point Interface (OCPI) is governed by the EVRoaming Foundation, a non-profit entity responsible for maintaining and evolving the protocol. The foundation operates a Work Group OCPI Development where full contributors participate in development. Proposals for changes or extensions enter via GitHub issues on the official repository (github.com/ocpi/ocpi), where they are reviewed and prioritized by the VDA/VDMA team. Issues are tagged with milestones indicating inclusion in future versions (e.g., V2.3.1 for minor fixes, V3.1.0 for backward-compatible changes). Historical outside-driven extensions include the Booking module (v1.1) and Accessibility extension, both developed in response to market needs and released in 2026. The foundation ensures free availability of OCPI, promoting global compatibility and transparency.

### VDA 5050

VDA 5050 is jointly developed by the German Association of the Automotive Industry (VDA) and the VDMA (Mechanical Engineering Industry Association), with technical input from the Institute for Material Handling and Logistics at KIT. The standard evolves through a community-driven process hosted on GitHub (github.com/VDA5050/vda5050), where anyone can raise issues or suggest improvements. Changes are reviewed in monthly core team meetings and tagged for inclusion in upcoming versions (V3.0.1, V3.1.0, etc.). Non-German and non-incumbent parties participate freely via GitHub, with no formal barriers. A service/energy companion document would structurally fit as a new module within the existing specification, likely under a new "ServiceSession" or "EnergyManagement" section, mirroring the modular design of current message types like "Order" or "InstantAction".

### GMG (Global Mining Guidelines Group)

The GMG Interoperability effort is coordinated through working groups under the GMG umbrella. Contributions are accepted from any member, with participation structured through three membership tiers: Leadership ($35,000 USD), Collaborator ($18,000 USD), and General ($6,000 USD). The working groups are open to members, who can propose new projects or serve as project leads depending on their tier. Leadership members can sit on up to 5 steering committees, while General members are limited to one. The group focuses on developing guidelines and white papers to accelerate innovation in mining, with active collaboration from global stakeholders.

### Reference Implementation Expectations

For OCPI, a reference implementation must pass the EVRoaming Test Tool (EVRTT) conformance tests, which validate compliance with OCPI 2.2.1 or 2.3.0. The implementation must be documented with clear API specifications and support key functionalities like authorization, tariff exchange, and session management. Open-source licensing (e.g., MIT) is encouraged but not mandated. For VDA 5050, while no formal conformance test exists, implementations are expected to adhere strictly to the JSON schemas in the GitHub repository, with comprehensive documentation of message structures and state transitions. The GMG does not require reference implementations for guidelines but expects contributors to provide detailed use cases and data models, often shared under open licenses like Creative Commons.

### Ecosystem Norms on Pre-Publishing Specs and Implementations

Publishing an open spec plus a working implementation before approaching the standards body strengthens the hand in all three ecosystems. For OCPI, a working implementation demonstrates technical viability and can accelerate adoption of a proposal. In the VDA 5050 community, a live implementation on GitHub serves as a de facto reference, increasing the likelihood of issue acceptance. Within GMG, a published spec with real-world application data enhances credibility and supports guideline development. In all cases, pre-publishing reduces perceived risk and provides concrete evidence of value.

## FOR CLAUDE CODE

### OCPI
- **Governing Body:** EVRoaming Foundation
- **Change Process:** Proposals via GitHub issues, reviewed by Work Group OCPI Development
- **Entry Requirements:** Full contributor status for direct participation; public GitHub for open proposals
- **Conformance Tool:** EVRoaming Test Tool (EVRTT) for OCPI 2.2.1/2.3.0
- **Cost:** €4,000 (one-time setup) + €1,200/year (hosting) for EVRF contributors; higher for non-contributors
- **License Expectation:** Open-source encouraged (MIT, Apache)
- **Documentation:** API specs, test reports, implementation guide

### VDA 5050
- **Governing Body:** VDA and VDMA
- **Change Process:** GitHub issues → core team review → milestone tagging
- **Entry Requirements:** Open to all via GitHub; VDA/VDMA membership for steering roles
- **Conformance Norm:** Adherence to JSON schemas; no formal test tool
- **Documentation:** Message definitions, state diagrams, example payloads
- **Structural Fit for Service/Energy Module:** New module in specification (e.g., ServiceSession)

### GMG
- **Governing Body:** Global Mining Guidelines Group
- **Change Process:** Member-proposed projects → working group development
- **Entry Requirements:** Membership (General: $6,000; Collaborator: $18,000; Leadership: $35,000)
- **Working Group Structure:** Tiered participation; Leadership can lead projects and sit on multiple committees
- **License Expectation:** Open data licenses (e.g., Creative Commons) for shared datasets
- **Documentation:** Use cases, data models, implementation guidelines

### Norms on Pre-Publishing
- **OCPI:** Strengthens hand; implementation shows viability
- **VDA 5050:** Strengthens hand; GitHub proof increases proposal acceptance
- **GMG:** Strengthens hand; real-world data supports guideline credibility

## OPEN QUESTIONS
- What is the exact process for non-members to contribute to GMG working groups?
- Are there any formal conformance tests planned for VDA 5050 beyond community validation?
- How does OCPI 3.0's draft status affect current implementation strategies?