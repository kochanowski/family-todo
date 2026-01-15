# ADR-001: Use CloudKit as Backend for Family To-Do App

**Status:** ✅ Accepted
**Date:** 2026-01-10
**Deciders:** Wojtek Kochanowski
**Technical Story:** Setup backend infrastructure for shared family task management

---

## Context and Problem Statement

Family To-Do App requires a backend solution to enable:
1. **Data synchronization** across user's multiple iOS devices (iPhone, iPad, Mac)
2. **Data sharing** between household members (typically 2 users: partners)
3. **Offline-first architecture** - app must work without internet connection
4. **Authentication** - secure user identification
5. **Real-time updates** - when partner completes a task, other sees it quickly

### Business Constraints:
- **Budget:** Minimal cost for MVP phase (2-10 users)
- **Time to market:** Fast implementation preferred
- **Team size:** Solo developer (initially)
- **Platform:** iOS-first, potential macOS support later

### Technical Requirements:
- iOS 17+ support
- SwiftUI compatibility
- Offline-first data persistence
- Secure data sharing between specific users
- Low maintenance overhead

---

## Decision Drivers

1. **Cost efficiency** - Free or very low cost for MVP with 2-10 users
2. **Development speed** - Fast setup, minimal backend code
3. **iOS integration** - Native support for Apple ecosystem
4. **Offline-first** - Built-in sync and conflict resolution
5. **Security** - Industry-standard encryption and privacy
6. **Scalability** - Can grow with user base (though not priority for MVP)
7. **Maintenance** - Low operational overhead (no server management)

---

## Considered Options

1. **CloudKit** - Apple's Backend-as-a-Service
2. **Firebase** - Google's Backend-as-a-Service
3. **Custom backend** - Self-hosted Node.js/Python API + PostgreSQL
4. **Supabase** - Open-source Firebase alternative
5. **Parse Server** - Open-source backend framework

---

## Decision Outcome

**Chosen option:** **CloudKit**

**Rationale:**
CloudKit best aligns with project goals for MVP phase:
- Zero backend cost for expected usage (2-10 users)
- Native iOS integration reduces development time
- Built-in offline-first architecture matches requirements
- Sign in with Apple integration is seamless
- No server infrastructure to maintain

---

## Positive Consequences

### Cost ✅
- **Free tier:** 1GB storage, 10GB transfer/month
- **Estimated usage:** ~1MB storage, ~3MB transfer for 2-10 users
- **No server costs:** No AWS EC2, database hosting, etc.
- **Only cost:** Apple Developer Account ($99/year) - already required for App Store

### Development Speed ✅
- **No backend code:** No REST API, no database schemas, no server deployment
- **Native SDKs:** First-class Swift support, excellent documentation
- **Xcode integration:** Built-in debugging tools
- **Estimated time saved:** 2-4 weeks vs custom backend

### Technical Benefits ✅
- **Offline-first:** Built-in conflict resolution and sync
- **Security:** End-to-end encryption for private data
- **Sharing:** CKShare API for multi-user households
- **Real-time updates:** Push notifications on data changes
- **Privacy:** Data stays in user's iCloud (not third-party server)

### Operational Benefits ✅
- **Zero maintenance:** No servers to patch, monitor, or scale
- **High availability:** Apple's infrastructure (99.9%+ uptime)
- **Automatic backups:** iCloud handles data redundancy
- **GDPR compliance:** Apple handles data privacy regulations

---

## Negative Consequences

### Platform Lock-in ⚠️
- **iOS/macOS only:** Cannot support Android or web without complete backend rewrite
- **Mitigation:** Product decision - iOS-first approach aligns with target market
- **Future:** If Android becomes required, can migrate to Firebase (see ADR-004 proposal)

### Apple Developer Account Required 💰
- **Cost:** $99/year mandatory
- **Dependency:** Requires Apple relationship
- **Mitigation:** Already necessary for App Store distribution

### Limited Query Capabilities ⚠️
- **CloudKit queries:** Less flexible than SQL (no JOINs, limited filtering)
- **Mitigation:** Simple data model doesn't require complex queries
- **Workaround:** Can use local SwiftData for complex queries after sync

### Vendor Lock-in Risk 📌
- **Dependency:** Tied to Apple's ecosystem and pricing
- **Risk:** Apple could change pricing or deprecate features
- **Mitigation:**
  - CloudKit is mature (launched 2014) and widely used
  - Can implement abstraction layer for future migration
  - Free tier unlikely to change dramatically (competitive with Firebase)

### User iCloud Requirement 👤
- **Dependency:** Users must be signed into iCloud
- **Impact:** Small % of iOS users don't use iCloud
- **Mitigation:**
  - Target audience (families managing households) likely uses iCloud
  - Can add educational onboarding for iCloud setup

---

## Alternatives Considered

### Option 2: Firebase

**Description:**
Google's Backend-as-a-Service with Firestore database, authentication, and Cloud Functions.

**Pros:**
- ✅ **Multiplatform:** iOS, Android, Web support
- ✅ **Rich features:** Analytics, push notifications, A/B testing
- ✅ **Generous free tier:** 1GB storage, 50K reads/day
- ✅ **Flexible queries:** More powerful than CloudKit
- ✅ **Large community:** Extensive tutorials and third-party tools

**Cons:**
- ❌ **More setup time:** Requires manual configuration (GoogleService-Info.plist, pods/SPM)
- ❌ **Not native iOS:** Third-party SDK, occasional Swift compatibility issues
- ❌ **Google dependency:** Privacy concerns for some users
- ❌ **Paid scaling:** Exceeding free tier can get expensive ($25-200/month for moderate usage)
- ❌ **Complexity:** More features = more cognitive load for simple use case

**Why not chosen:**
- MVP doesn't need Android support (iOS-first strategy)
- CloudKit's native integration saves 1-2 weeks development time
- Firebase's extra features add unnecessary complexity for family task app
- **Decision:** Could revisit if Android becomes requirement (see ADR-004 proposal)

---

### Option 3: Custom Backend (Node.js + PostgreSQL)

**Description:**
Self-hosted API server (Express.js, FastAPI) with PostgreSQL database, deployed on AWS/DigitalOcean.

**Pros:**
- ✅ **Full control:** Complete flexibility over data model, business logic, scaling
- ✅ **No vendor lock-in:** Can switch cloud providers
- ✅ **SQL power:** Complex queries, transactions, stored procedures
- ✅ **Multiplatform ready:** Same API for iOS/Android/Web

**Cons:**
- ❌ **High development cost:** 3-6 weeks to build MVP backend
- ❌ **Infrastructure costs:** $10-50/month minimum (server, database, load balancer)
- ❌ **Maintenance burden:** Security patches, database backups, monitoring, on-call
- ❌ **Offline-first complexity:** Must implement sync logic manually (conflict resolution, queues)
- ❌ **Solo developer risk:** Single point of failure for operations
- ❌ **Time to market:** Delays MVP launch by 4-8 weeks

**Why not chosen:**
- MVP doesn't justify 3-6 weeks backend development
- CloudKit provides same functionality for $0/month
- No resources for 24/7 operational monitoring
- **Decision:** Only consider if project outgrows BaaS limitations (10K+ users)

---

### Option 4: Supabase

**Description:**
Open-source Firebase alternative with PostgreSQL, real-time subscriptions, and REST API.

**Pros:**
- ✅ **PostgreSQL:** Full SQL power (JOINs, complex queries)
- ✅ **Open source:** Can self-host if needed
- ✅ **Free tier:** 500MB storage, 2GB transfer
- ✅ **Real-time:** WebSocket subscriptions for live updates

**Cons:**
- ❌ **Third-party SDK:** Not as polished as Firebase or CloudKit
- ❌ **Setup complexity:** Requires manual table schemas, RLS policies
- ❌ **Less mature:** Newer platform (founded 2020), smaller ecosystem
- ❌ **No offline-first:** Must implement client-side caching manually

**Why not chosen:**
- Complexity similar to Firebase but less mature ecosystem
- CloudKit's native iOS integration is simpler
- No compelling reason to choose over CloudKit or Firebase

---

### Option 5: Parse Server

**Description:**
Open-source backend framework (originally by Facebook), self-hosted or cloud-hosted.

**Pros:**
- ✅ **Open source:** Full control, can self-host
- ✅ **Mature:** Battle-tested since 2013

**Cons:**
- ❌ **Declining ecosystem:** Less active development since Facebook sunset
- ❌ **Setup overhead:** Requires server management
- ❌ **Outdated iOS SDK:** Swift support not great

**Why not chosen:**
- Declining community and ecosystem
- No advantage over CloudKit or Firebase for this use case

---

## Implementation Plan

### Phase 1: Schema Design (Week 1)
1. Define CloudKit record types: Household, Member, Task, RecurringChore, Area
2. Set up relationships and indexes
3. Configure security (private vs shared database)

### Phase 2: CloudKit Integration (Week 2-3)
1. Add iCloud capability in Xcode
2. Implement CloudKitManager singleton
3. Create CRUD operations for each entity
4. Add offline-first caching with SwiftData

### Phase 3: Sharing Implementation (Week 4)
1. Implement CKShare for household invitations
2. Add share link generation
3. Handle incoming share acceptances
4. Test multi-user sync

### Phase 4: Testing (Week 5)
1. Test offline mode (Airplane Mode)
2. Test conflict resolution
3. Test sharing between two iCloud accounts
4. Performance testing (sync speed)

---

## Validation Metrics

**Success criteria for CloudKit choice:**
- ✅ MVP launches within 8 weeks (vs 12+ weeks with custom backend)
- ✅ Monthly costs < $10/month for first year
- ✅ Zero operational incidents (no server downtime)
- ✅ Offline-first works seamlessly (no data loss)
- ✅ Sharing between partners works reliably

**Re-evaluation triggers:**
- ❌ Android support becomes requirement → Consider Firebase (ADR-004)
- ❌ User base exceeds 1000 active users → Re-evaluate costs
- ❌ Complex query needs emerge → Consider adding custom backend layer

---

## Related Decisions

- **ADR-002** (proposed): Use SwiftData for local caching layer
- **ADR-003** (proposed): Use SwiftUI + MVVM architecture for views
- **ADR-004** (proposed): Migration path from CloudKit to Firebase (if needed)

---

## References

- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [CloudKit Pricing](https://developer.apple.com/icloud/cloudkit/)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [WWDC 2021: CloudKit Best Practices](https://developer.apple.com/videos/play/wwdc2021/10003/)
- [Sharing CloudKit Data](https://developer.apple.com/documentation/cloudkit/shared_records)

---

**Last Updated:** 2026-01-10
**Next Review:** 2026-04-10 (after 3 months of usage)
