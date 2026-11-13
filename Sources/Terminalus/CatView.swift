import AppKit

/// Настроение питомцев = сводка по всем вкладкам.
enum CatMood {
    case sleep   // всё тихо — Тян спит, у Бэна свои дела, иногда они беснуются вместе
    case play    // Claude работает — Тян гоняет клубок, Бэн грызёт кость
    case alert   // Claude ждёт ответа — Тян машет лапой, Бэн лает
    case sad     // лимиты почти кончились — оба грустят и спят
}

/// Тян, Бэн и будка в строке заголовка окна. Лежит поверх заголовка, но «прозрачен» для мыши везде,
/// кроме самих питомцев и клубка — поэтому окно по-прежнему двигается за заголовок.
final class CatView: NSView {
    var mood: CatMood = .sleep
    /// Левая граница «территории» (правее кнопок окна и логотипа) — задаёт окно.
    var leftLimit: CGFloat = 86

    // MARK: Размеры

    /// Масштаб под высоту строки заголовка (питомцы ~27 pt, строка обычно 28 pt).
    private var k: CGFloat { min(1, max(0.5, (bounds.height - 2) / CatArt.height)) }
    private var catW: CGFloat { CatArt.width * k }
    private var catH: CGFloat { CatArt.height * k }
    private var dogW: CGFloat { DogArt.width * k }
    private var dogH: CGFloat { DogArt.height * k }
    private var houseW: CGFloat { DogArt.houseWidth * k }
    private var ballSize: CGFloat { 13 * k }
    private let baseY: CGFloat = 1

    private var houseX: CGFloat { bounds.width - houseW - 10 }
    private var rightLimit: CGFloat { max(leftLimit + catW * 2.2, houseX - 12) }   // правая граница клубка и Тян
    private var dogHome: CGFloat { houseX - dogW - 6 }
    private var logoCornerX: CGFloat { leftLimit - 6 }                              // «угол» логотипа

    // MARK: Состояние

    // Тян
    private var catX: CGFloat = 250
    private var catFacingRight = true
    private var catMoving = false
    private var catRate: CGFloat = 1
    // клубок
    private var ballX: CGFloat = 330
    private var ballV: CGFloat = 0
    private var ballAngle: CGFloat = 0
    private var pauseUntil = Date.distantPast
    private var draggingBall = false
    private var lastDragX: CGFloat = 0
    private var lastDragTime = Date()
    private var dragVel: CGFloat = 0
    // Бэн
    private enum DogAct { case sleep, gnaw, bark, walk, mark, sit }
    private var dogX: CGFloat = 520
    private var dogFacingRight = false
    private var dogAct: DogAct = .sleep
    private var dogStart = Date()
    private var dogUntil = Date().addingTimeInterval(8)
    private var dogGoal: CGFloat?
    private var dogAfter: DogAct = .sit
    private var dogAfterDuration: TimeInterval = 3
    private var dogMarkRight = true
    private var dogRate: CGFloat = 1
    private var dropTimer: CGFloat = 0
    private var puddle: (x: CGFloat, start: Date)?
    private var drops: [(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, age: CGFloat)] = []
    // игра вдвоём
    private struct Play {
        var end: Date
        var phase: Int            // 0 — Бэн бежит к Тян, 1 — поклон, 2 — догонялки
        var phaseUntil: Date
        var dogChases: Bool
        var runDir: CGFloat
        var hopUntil: Date
    }
    private var play: Play?
    private var nextPlay = Date().addingTimeInterval(Double.random(in: 25...45))
    private var playCatPose: CatPose?
    private var playDogPose: DogPose?
    // общее
    private var animT: CGFloat = 0
    private var clock: CGFloat = 0
    private var celebrateStart: Date?
    private var petUntil = Date.distantPast
    /// Сердечки при поглаживании: dx — смещение от кошки (движутся вместе с ней), y — высота над полом.
    private var hearts: [(dx: CGFloat, y: CGFloat, age: CGFloat, phase: CGFloat)] = []
    private var timer: Timer?
    private var last = Date()

    private let walkSpeed: CGFloat = 42
    private let chaseSpeed: CGFloat = 52
    private let dogWalkSpeed: CGFloat = 55
    private let catRunSpeed: CGFloat = 118
    private let dogRunSpeed: CGFloat = 128
    /// Частота шага подобрана под скорость, чтобы лапы не «скользили».
    private let catStepRate: CGFloat = 12.5 / 9
    private let dogStepRate: CGFloat = 2.9

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Тян и Бэн"
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Жизненный цикл

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: Settings.petEconomy ? 1.0 / 15.0 : 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickTimer() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        last = clockNow()
    }

    /// Режим «15 кадров» переключили в меню.
    func applyFrameRate() { if window != nil { startTimer() } }

    deinit { timer?.invalidate() }

    private func tickTimer() {
        let now = clockNow()
        defer { last = now }
        guard !isHidden, let w = window, w.occlusionState.contains(.visible) else { return }
        advance(CGFloat(min(0.1, now.timeIntervalSince(last))))
    }

    /// Задача завершилась — все радуются.
    func celebrate() { celebrateStart = clockNow() }

    // MARK: Шаг симуляции

    /// Текущее время (подменяется в тестах/превью, чтобы симуляция шла быстрее реального времени).
    var clockOverride: Date?
    private func clockNow() -> Date { clockOverride ?? Date() }

    private var placed = false

    /// Чем сейчас занят Бэн (для отладки и превью).
    var dogActivity: String { play != nil ? "play" : "\(dogAct)" }

    func advance(_ dt: CGFloat) {
        // При создании у вида ещё нулевая ширина — расставляем всех по местам после первой раскладки.
        if !placed, bounds.width > 200 {
            placed = true
            dogX = dogHome
            catX = leftLimit + 56
            ballX = leftLimit + 120
            dogFacingRight = false
        }
        clock += dt
        animT += dt
        let now = clockNow()
        let celebrating = celebrateStart.map { now.timeIntervalSince($0) < 2.4 } ?? false
        if !celebrating { celebrateStart = nil }

        stepBall(dt)

        // игра вдвоём: только когда все агенты молчат; прерывается, как только что-то происходит
        if play == nil, mood == .sleep, !celebrating, now >= petUntil, now >= nextPlay, dogAct != .bark { startPlay(now) }
        if play != nil, mood != .sleep || celebrating || now < petUntil { endPlay(now) }

        if play != nil {
            stepPlay(dt, now)
        } else {
            playCatPose = nil
            playDogPose = nil
            catMoving = false
            catRate = 1
            if !celebrating && now >= petUntil { stepCat(dt, now) }
            catX = max(leftLimit - 8, min(rightLimit - catW, catX))
            stepDog(dt, now)
            if mood != .play || celebrating || now < petUntil { separateBall() }
        }

        hearts = hearts.compactMap { var h = $0; h.age += dt; h.y += 15 * dt; return h.age < 1.5 ? h : nil }
        if now < petUntil, Int.random(in: 0..<5) == 0 {            // рождаются снизу, у самой кошки
            hearts.append((dx: catW * CGFloat.random(in: 0.25...0.8), y: 3, age: 0, phase: CGFloat.random(in: 0...6)))
        }
        drops = drops.compactMap { var d = $0; d.age += dt; d.x += d.vx * dt; d.vy -= 70 * dt; d.y += d.vy * dt
            return (d.age < 0.6 && d.y > 0) ? d : nil }
        if let pd = puddle, now.timeIntervalSince(pd.start) > 7 { puddle = nil }
        needsDisplay = true
    }

    // MARK: Клубок и Тян

    private func stepBall(_ dt: CGFloat) {
        guard !draggingBall else { return }
        ballX += ballV * dt
        ballV *= pow(0.5, dt)
        if abs(ballV) < 4 { ballV = 0 }
        let lo = leftLimit, hi = rightLimit - ballSize
        if ballX < lo { ballX = lo; ballV = abs(ballV) * 0.7 }
        if ballX > hi { ballX = hi; ballV = -abs(ballV) * 0.7 }
        ballAngle += ballV * dt / 6.5
    }

    private func walkCat(to x: CGFloat, _ dt: CGFloat) {
        let d = x - catX
        guard abs(d) > 3 else { return }
        catFacingRight = d > 0
        catX += (d > 0 ? 1 : -1) * walkSpeed * dt
        catMoving = true
    }

    private func chaseBall(_ dt: CGFloat, _ now: Date) {
        guard now >= pauseUntil else { return }
        let right = ballX + ballSize / 2 > catX + catW / 2
        catFacingRight = right
        let front = catX + (right ? catW - 4 * k : 4 * k)
        let gap = right ? ballX - front : front - (ballX + ballSize)
        if gap > 4 {
            catX += (right ? 1 : -1) * chaseSpeed * dt
            catMoving = true
        } else {                                     // удар лапой
            // У стены бьём в сторону середины (иначе мяч отскакивает от стены обратно и так до бесконечности).
            let zone: CGFloat = 110
            var dir: CGFloat = right ? 1 : -1
            if ballX > rightLimit - ballSize - zone { dir = -1 }
            else if ballX < leftLimit + zone { dir = 1 }
            ballV = dir * CGFloat.random(in: 140...250)
            pauseUntil = now.addingTimeInterval(0.35)
        }
    }

    private func stepCat(_ dt: CGFloat, _ now: Date) {
        switch mood {
        case .play:  chaseBall(dt, now)
        case .sleep, .sad: walkCat(to: leftLimit + 56, dt)
        case .alert: walkCat(to: (leftLimit + rightLimit) / 2 - catW / 2, dt)
        }
        catRate = catStepRate
    }

    /// Если клубок лежит под кошкой (не в игре) — откатываем его в сторону, где больше места.
    private func separateBall() {
        guard !draggingBall, abs(ballV) < 50 else { return }
        let overlaps = ballX + ballSize > catX + 6 * k && ballX < catX + catW - 6 * k
        guard overlaps else { return }
        let roomRight = rightLimit - (catX + catW)
        let roomLeft = catX - leftLimit
        ballV = (roomRight >= roomLeft ? 1 : -1) * 90
    }

    // MARK: Бэн

    private func startDog(_ act: DogAct, _ duration: TimeInterval, _ now: Date) {
        dogAct = act
        dogStart = now
        dogUntil = now.addingTimeInterval(duration)
    }

    private func dogGo(to x: CGFloat, then act: DogAct, for duration: TimeInterval) {
        dogGoal = x
        dogAfter = act
        dogAfterDuration = duration
        dogAct = .walk
    }

    private func chooseDogAct(_ now: Date) {
        let home = dogHome
        func sleep() {
            if abs(dogX - home) > 6 { dogGo(to: home, then: .sleep, for: Double.random(in: 16...30)) }
            else { startDog(.sleep, Double.random(in: 16...30), now) }
        }
        func gnaw() {
            let spot = home - 16
            if abs(dogX - spot) > 6 { dogGo(to: spot, then: .gnaw, for: Double.random(in: 9...16)) }
            else { startDog(.gnaw, Double.random(in: 9...16), now) }
        }
        func mark() {
            dogMarkRight = Bool.random()                       // угол будки или угол логотипа
            dogGo(to: dogMarkRight ? houseX - dogW * 0.55 : logoCornerX, then: .mark, for: 2.8)
        }
        func wander() {
            let lo = max(leftLimit, home - 200)
            dogGo(to: CGFloat.random(in: lo...max(lo, home)), then: .sit, for: Double.random(in: 3...6))
        }
        let r = Double.random(in: 0..<1)
        switch mood {
        case .alert: startDog(.bark, 2.2, now)
        case .sad:   sleep()
        case .play:  if r < 0.5 { gnaw() } else if r < 0.8 { sleep() } else { mark() }
        case .sleep:
            if r < 0.25 { sleep() } else if r < 0.5 { gnaw() } else if r < 0.75 { mark() }
            else if r < 0.9 { wander() } else { startDog(.sit, Double.random(in: 3...6), now) }
        }
    }

    private func stepDog(_ dt: CGFloat, _ now: Date) {
        dogRate = dogStepRate
        if mood == .alert && dogAct != .bark { startDog(.bark, 2.2, now) }

        switch dogAct {
        case .walk:
            guard let g = dogGoal else { startDog(.sit, 2, now); break }
            let d = g - dogX
            if abs(d) < 3 {
                dogX = g
                dogGoal = nil
                if dogAfter == .mark { dogFacingRight = dogMarkRight }
                startDog(dogAfter, dogAfterDuration, now)
            } else {
                dogFacingRight = d > 0
                dogX += (d > 0 ? 1 : -1) * dogWalkSpeed * dt
            }
        case .bark:
            if now >= dogUntil { if mood == .alert { startDog(.bark, 2.2, now) } else { chooseDogAct(now) } }
        case .mark:
            let t = now.timeIntervalSince(dogStart)
            dropTimer += dt
            let legX = dogX + dogW * (dogFacingRight ? 0.15 : 0.85)      // там, где поднята задняя лапа
            if t > 0.5 && t < 2.2 {
                if puddle == nil { puddle = (x: legX, start: now) }
                if dropTimer > 0.09 {
                    dropTimer = 0
                    drops.append((x: legX + CGFloat.random(in: -0.6...0.6), y: dogH * 0.16, vx: 0, vy: 1, age: 0))
                }
            }
            if now >= dogUntil { chooseDogAct(now) }
        default:
            if now >= dogUntil { chooseDogAct(now) }
        }
        dogX = max(leftLimit - 24, min(bounds.width - dogW - 4, dogX))
    }

    // MARK: Игра вдвоём (Тян и Бэн беснуются, пока агенты молчат)

    private func startPlay(_ now: Date) {
        play = Play(end: now.addingTimeInterval(Double.random(in: 10...15)), phase: 0, phaseUntil: now,
                    dogChases: false, runDir: 1, hopUntil: .distantPast)
        dogGoal = nil
    }

    /// Двойной клик по Тян: позвать Бэна играть (работает, когда агенты не заняты).
    func callToPlay() {
        guard mood == .sleep, play == nil else { return }
        petUntil = .distantPast
        startPlay(clockNow())
    }

    private func endPlay(_ now: Date) {
        play = nil
        nextPlay = now.addingTimeInterval(Double.random(in: 45...100))
        dogGo(to: dogHome, then: .sleep, for: Double.random(in: 16...30))
    }

    private func stepPlay(_ dt: CGFloat, _ now: Date) {
        guard var p = play else { return }
        let zoneLo = leftLimit - 8
        let zoneHi = houseX - 10
        catMoving = false
        playCatPose = nil
        playDogPose = nil

        func moveCat(_ dir: CGFloat, _ speed: CGFloat) {
            catFacingRight = dir > 0
            catX += dir * speed * dt
            catMoving = true
            catRate = catStepRate * speed / walkSpeed * 0.55
            playCatPose = .walk
        }
        func moveDog(_ dir: CGFloat, _ speed: CGFloat) {
            dogFacingRight = dir > 0
            dogX += dir * speed * dt
            dogRate = dogStepRate * speed / dogWalkSpeed * 0.55
            playDogPose = .walk
        }

        switch p.phase {
        case 0:   // Тян проснулась, Бэн мчится к ней
            playCatPose = .sit
            let target = catX + catW + 2
            let d = target - dogX
            catFacingRight = dogX > catX
            if abs(d) < 6 { p.phase = 1; p.phaseUntil = now.addingTimeInterval(0.9) }
            else { moveDog(d > 0 ? 1 : -1, dogRunSpeed) }
        case 1:   // приглашение к игре: Бэн кланяется, Тян машет лапой
            playDogPose = .bow
            playCatPose = .wave
            dogFacingRight = false
            catFacingRight = true
            if now >= p.phaseUntil {
                p.phase = 2
                p.dogChases = false          // сначала Тян убегает, Бэн догоняет
                p.runDir = Bool.random() ? 1 : -1
                p.hopUntil = now.addingTimeInterval(0.4)
            }
        default:  // догонялки
            let runnerIsCat = !p.dogChases
            let runnerX = runnerIsCat ? catX : dogX
            let chaserX = runnerIsCat ? dogX : catX
            let runnerW = runnerIsCat ? catW : dogW
            let chaserW = runnerIsCat ? dogW : catW
            // убегающий бежит в свою сторону и разворачивается у краёв
            if runnerIsCat {
                if catX + catW >= zoneHi && p.runDir > 0 { p.runDir = -1 }
                if catX <= zoneLo && p.runDir < 0 { p.runDir = 1 }
                moveCat(p.runDir, catRunSpeed)
                let toward: CGFloat = (catX + catW / 2) > (dogX + dogW / 2) ? 1 : -1
                moveDog(toward, dogRunSpeed * 0.9)
            } else {
                if dogX + dogW >= zoneHi && p.runDir > 0 { p.runDir = -1 }
                if dogX <= zoneLo && p.runDir < 0 { p.runDir = 1 }
                moveDog(p.runDir, dogRunSpeed)
                let toward: CGFloat = (dogX + dogW / 2) > (catX + catW / 2) ? 1 : -1
                moveCat(toward, catRunSpeed * 0.9)
            }
            // догнали → меняются ролями, прыжок от радости
            let gap = abs((chaserX + chaserW / 2) - (runnerX + runnerW / 2))
            if gap < (chaserW + runnerW) * 0.32 && now >= p.hopUntil {
                p.dogChases.toggle()
                p.hopUntil = now.addingTimeInterval(0.45)
                let newRunnerWasChaser = !(!p.dogChases)   // тот, кто только что догонял, теперь убегает
                _ = newRunnerWasChaser
                p.runDir = (runnerX >= chaserX) ? -1 : 1     // убегает от только что догонявшего в обратную сторону
            }
            if now < p.hopUntil { playCatPose = .jump; playDogPose = .jump }
        }
        catX = max(zoneLo, min(zoneHi - catW, catX))
        dogX = max(zoneLo, min(zoneHi - dogW, dogX))
        play = p
        if now >= p.end { endPlay(now) }
    }

    // MARK: Рисование

    override func draw(_ dirtyRect: NSRect) {
        let now = clockNow()
        let celebrating = celebrateStart.map { now.timeIntervalSince($0) < 2.4 } ?? false
        let celebT = celebrateStart.map { CGFloat(now.timeIntervalSince($0)) } ?? 0
        let hop = celebrating ? abs(sin(celebT * .pi * 2.2)) * 7 : 0

        // будка и кость
        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState()
            var tr = AffineTransform()
            tr.translate(x: houseX, y: baseY)
            tr.scale(k)
            (tr as NSAffineTransform).concat()
            DogArt.drawHouse(at: .zero)
            ctx.restoreGraphicsState()
        }
        if dogAct != .gnaw || play != nil {                  // кость лежит у будки
            DogArt.drawBone(center: NSPoint(x: dogHome - 30 * k, y: baseY + 2 * k), angle: 0.18, length: 12 * k)
        }

        // клубок
        CatArt.drawYarn(center: NSPoint(x: ballX + ballSize / 2, y: baseY + ballSize / 2),
                        radius: ballSize / 2, angle: ballAngle)

        // Тян
        let catPose: CatPose
        var catT = animT
        if celebrating {
            catPose = .jump
        } else if let pp = playCatPose {
            catPose = pp
            if pp == .walk { catT = animT * catRate }
        } else if now < petUntil {
            catPose = .pet
        } else if catMoving {
            catPose = .walk
            catT = animT * catRate
        } else {
            switch mood {
            case .play:  catPose = .sit
            case .sleep: catPose = .sleep
            case .alert: catPose = .wave
            case .sad:   catPose = .sad
            }
        }
        var catHop: CGFloat = hop
        if let p = play, now < p.hopUntil, playCatPose == .jump { catHop = abs(sin(CGFloat(p.hopUntil.timeIntervalSince(now)) / 0.45 * .pi)) * 6 }
        drawActor(x: catX, y: baseY + catHop) {
            CatArt.draw(catPose, t: catT, at: .zero, flipped: !self.catFacingRight)
        }

        // Бэн
        let dogPose: DogPose
        var dogT = animT
        if celebrating {
            dogPose = .jump
        } else if let pp = playDogPose {
            dogPose = pp
            if pp == .walk { dogT = animT * dogRate }
        } else {
            switch dogAct {
            case .sleep: dogPose = .sleep
            case .gnaw:  dogPose = .gnaw
            case .bark:  dogPose = .bark
            case .mark:  dogPose = .mark
            case .sit:   dogPose = .sit
            case .walk:  dogPose = .walk; dogT = animT * dogRate
            }
        }
        var dogHopY: CGFloat = hop
        if let p = play, now < p.hopUntil, playDogPose == .jump { dogHopY = abs(sin(CGFloat(p.hopUntil.timeIntervalSince(now)) / 0.45 * .pi)) * 6 }
        drawActor(x: dogX, y: baseY + dogHopY) {
            DogArt.draw(dogPose, t: dogT, at: .zero, flipped: !self.dogFacingRight)
        }
        if dogPose == .gnaw {                                 // кость между лапами
            let bx = dogX + dogW * (dogFacingRight ? 0.88 : 0.12)
            DogArt.drawBone(center: NSPoint(x: bx, y: baseY + 3.2 * k), angle: dogFacingRight ? 0.45 : -0.45, length: 12 * k)
        }

        // эффекты
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, color: NSColor, align: CGFloat = 0.5) {
            let a = NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: color])
            a.draw(at: NSPoint(x: x - a.size().width * align, y: y))
        }

        if !celebrating && now >= petUntil && play == nil {
            let headY = baseY + catH - 11
            switch mood {
            case .sleep where !catMoving:                     // z-z-z у Тян
                for i in 0..<3 {
                    let ph = (clock * 0.45 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
                    text("z", catX + catW * 0.82 + ph * 10, baseY + catH * 0.5 + ph * 9,
                         size: 7 + ph * 4, color: NSColor.white.withAlphaComponent(0.8 * (1 - ph)))
                }
            case .alert where Int(clock * 3) % 2 == 0:
                text("!", catX + catW * (catFacingRight ? 0.92 : 0.08), headY, size: 14,
                     color: NSColor(srgbRed: 1, green: 0.82, blue: 0.22, alpha: 1))
            case .sad where !catMoving:
                text("…", catX + catW * (catFacingRight ? 0.92 : 0.08), headY, size: 12, color: NSColor.white.withAlphaComponent(0.5))
            default: break
            }
        }
        if dogPose == .sleep && play == nil && !celebrating {  // z-z-z у Бэна
            for i in 0..<3 {
                let ph = (clock * 0.5 + CGFloat(i) / 3 + 0.3).truncatingRemainder(dividingBy: 1)
                text("z", dogX + dogW * (dogFacingRight ? 0.82 : 0.18) + ph * 8 * (dogFacingRight ? 1 : -1),
                     baseY + dogH * 0.4 + ph * 8, size: 6 + ph * 3, color: NSColor.white.withAlphaComponent(0.8 * (1 - ph)))
            }
        }
        if dogPose == .bark {                                  // «ГАВ!» — только визуально
            let pulse = 0.75 + 0.25 * abs(sin(clock * 9))
            let nx = dogX + dogW * (dogFacingRight ? 1.02 : -0.02)
            text("ГАВ!", nx + (dogFacingRight ? 1 : -1) * 2, baseY + dogH * 0.5, size: 8 * pulse + 1,
                 color: NSColor(srgbRed: 1, green: 0.88, blue: 0.4, alpha: 1), align: dogFacingRight ? 0 : 1)
        }
        if let pd = puddle {                                   // лужица, высыхает за несколько секунд
            let age = CGFloat(now.timeIntervalSince(pd.start))
            let w = min(8, age * 6) * k, a = max(0, 1 - age / 7) * 0.85
            NSColor(srgbRed: 0.98, green: 0.84, blue: 0.22, alpha: a).setFill()
            NSBezierPath(ovalIn: NSRect(x: pd.x - w / 2, y: baseY - 0.2, width: w, height: 1.8 * k)).fill()
        }
        for d in drops {                                       // метка угла
            NSColor(srgbRed: 1, green: 0.88, blue: 0.25, alpha: max(0, 1 - d.age / 0.6)).setFill()
            NSRect(x: d.x, y: baseY + d.y, width: 1.8, height: 1.8).fill()
        }
        for h in hearts {                                      // сердечки поднимаются за кошкой
            let x = catX + h.dx + sin(h.age * 5 + h.phase) * 2.5
            let alpha = h.age < 1.0 ? 1 : max(0, 1 - (h.age - 1.0) / 0.5)
            text("♥", x, baseY + h.y, size: 9, color: NSColor(srgbRed: 1, green: 0.42, blue: 0.55, alpha: alpha))
        }

        if celebrating {                                       // конфетти
            let t = celebT
            let colors: [NSColor] = [.systemPink, .systemYellow, .systemGreen, .systemBlue, .systemOrange]
            for i in 0..<16 {
                let a = CGFloat(i) * 0.9 + 0.3
                let r = t * (14 + CGFloat(i % 5) * 7)
                let cx = i % 2 == 0 ? catX + catW / 2 : dogX + dogW / 2
                let x = cx + cos(a) * r * 1.6
                let y = baseY + catH * 0.6 + sin(a) * r * 0.5 + 4 - t * t * 3
                colors[i % colors.count].withAlphaComponent(max(0, 1 - t / 2.4)).setFill()
                NSRect(x: x, y: y, width: 3, height: 3).fill()
            }
        }
    }

    private func drawActor(x: CGFloat, y: CGFloat, _ body: () -> Void) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        var tr = AffineTransform()
        tr.translate(x: x, y: y)
        tr.scale(k)
        (tr as NSAffineTransform).concat()
        body()
        ctx.restoreGraphicsState()
    }

    // MARK: Мышь: гладим Тян, дразним Бэна, кидаем клубок

    private var catRect: NSRect { NSRect(x: catX, y: baseY, width: catW, height: catH).insetBy(dx: -2, dy: -2) }
    private var dogRect: NSRect { NSRect(x: dogX, y: baseY, width: dogW, height: dogH).insetBy(dx: -2, dy: -2) }
    private var ballRect: NSRect { NSRect(x: ballX, y: baseY, width: ballSize, height: ballSize).insetBy(dx: -3, dy: -3) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let p = convert(point, from: superview)
        return (ballRect.contains(p) || catRect.contains(p) || dogRect.contains(p)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if ballRect.contains(p) {
            draggingBall = true
            ballV = 0
            lastDragX = p.x
            lastDragTime = clockNow()
            dragVel = 0
        } else if dogRect.contains(p) && !catRect.contains(p) {
            if play != nil { endPlay(clockNow()) }
            startDog(.bark, 1.6, clockNow())                      // Бэн лает
        } else if catRect.contains(p) {
            if event.clickCount >= 2 { callToPlay() }         // двойной клик — позвать Бэна играть
            else { petUntil = clockNow().addingTimeInterval(2.2) } // Тян мурчит
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggingBall else { return }
        let p = convert(event.locationInWindow, from: nil)
        let now = clockNow()
        let dt = CGFloat(max(0.001, now.timeIntervalSince(lastDragTime)))
        dragVel = (p.x - lastDragX) / dt
        lastDragX = p.x
        lastDragTime = now
        ballX = max(leftLimit, min(rightLimit - ballSize, p.x - ballSize / 2))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard draggingBall else { return }
        draggingBall = false
        ballV = max(-420, min(420, dragVel))                  // бросок
    }
}
