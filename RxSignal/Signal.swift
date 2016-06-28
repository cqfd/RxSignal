//
//  Signal.swift
//  RxSignal
//
//  Created by Alan O'Donnell on 6/28/16.
//
//

import Foundation
import RxSwift
import RxSwiftExt
import RxCocoa

class Signal<E>: ObservableConvertibleType {
    private let _out: Variable<E>
    var value: E { return _out.value }
    init(out: Variable<E>) {
        _out = out
    }
    func map<R>(selector: E -> R) -> Signal<R> {
        return MapSignal(source: self, selector: selector)
    }
    static func map<R>(selector: E -> R) -> Signal<E> -> Signal<R> {
        return { $0.map(selector) }
    }
    func flatMap<R>(selector: E -> Signal<R>) -> Signal<R> {
        return FlatMapSignal(source: self, selector: selector)
    }
    func flatMapLatest<R>(selector: E -> Signal<R>) -> Signal<R> {
        return FlatMapLatestSignal(source: self, selector: selector)
    }
    static func combineLatest<A, B>(a: Signal<A>, _ b: Signal<B>, resultSelector: (A, B) -> E) -> Signal<E> {
        return CombineLatest2Signal(a: a, b: b, resultSelector: resultSelector)
    }
    func asObservable() -> Observable<E> {
        return Observable.create(self._subscribe).shareReplayLatestWhileConnected()
    }
    private func _subscribe<O: ObserverType where O.E == E>(observer: O) -> Disposable {
        return _out.asObservable().subscribe(observer)
    }
}

class RawSignal<E>: Signal<E> {
    private let _subsequentValues: Observable<E>
    private let disposeBag = DisposeBag()
    
    init(initialValue: E, subsequentValues: Observable<E>) {
        _subsequentValues = subsequentValues
        super.init(out: Variable(initialValue))
        subsequentValues.bindTo(_out).addDisposableTo(disposeBag)
    }
    
    override func map<R>(selector: E -> R) -> Signal<R> {
        return RawSignal<R>(initialValue: selector(value), subsequentValues: _subsequentValues.map(selector))
    }
}

class MapSignal<In, Out>: Signal<Out> {
    private let _source: Signal<In>
    private let _selector: In -> Out
    private let disposeBag = DisposeBag()
    
    init(source: Signal<In>, selector: In -> Out) {
        _source = source
        _selector = selector
        super.init(out: Variable(selector(_source.value)))
        let subsequentValues = _source.asObservable().skip(1).map(selector)
        subsequentValues.bindTo(_out).addDisposableTo(disposeBag)
    }
    
    override func map<R>(selector: Out -> R) -> Signal<R> {
        return MapSignal<In, R>(source: _source, selector: compose(selector, _selector))
    }
}

class FlatMapSignal<In, Out>: Signal<Out> {
    private let _source: Signal<In>
    private let _selector: In -> Signal<Out>
    private let disposeBag = DisposeBag()
    
    init(source: Signal<In>, selector: In -> Signal<Out>) {
        _source = source
        _selector = selector
        let initialSignal = selector(_source.value)
        super.init(out: Variable(initialSignal.value))
        let subsequentValues = Observable.of(
            initialSignal.asObservable().skip(1),
            _source.asObservable().skip(1).flatMap(selector)
            ).merge()
        subsequentValues.bindTo(_out).addDisposableTo(disposeBag)
    }
    
    override func map<R>(selector: Out -> R) -> Signal<R> {
        return FlatMapSignal<In, R>(source: _source, selector: compose(Signal.map(selector), _selector))
    }
}

class FlatMapLatestSignal<In, Out>: Signal<Out> {
    private let _source: Signal<In>
    private let _selector: In -> Signal<Out>
    private let disposeBag = DisposeBag()
    
    init(source: Signal<In>, selector: In -> Signal<Out>) {
        _source = source
        _selector = selector
        let initialSignal = selector(_source.value)
        super.init(out: Variable(initialSignal.value))
        let subsequentValues = Observable.cascade([
            initialSignal.asObservable().skip(1),
            _source.asObservable().skip(1).flatMapLatest(selector)
            ])
        subsequentValues.bindTo(_out).addDisposableTo(disposeBag)
    }
    
    override func map<R>(selector: Out -> R) -> Signal<R> {
        return FlatMapLatestSignal<In, R>(source: _source, selector: compose(Signal.map(selector), _selector))
    }
}

class CombineLatest2Signal<A, B, E>: Signal<E> {
    private let _a: Signal<A>
    private let _b: Signal<B>
    private let _resultSelector: (A, B) -> E
    private let disposeBag = DisposeBag()
    
    init(a: Signal<A>, b: Signal<B>, resultSelector: (A, B) -> E) {
        _a = a
        _b = b
        _resultSelector = resultSelector
        super.init(out: Variable(resultSelector(a.value, b.value)))
        let subsequentValues = Observable.combineLatest(
            a.asObservable(), b.asObservable(),
            resultSelector: { $0 }
            ).skip(1).map(resultSelector)
        subsequentValues.bindTo(_out).addDisposableTo(disposeBag)
    }
    
    override func map<R>(selector: E -> R) -> Signal<R> {
        return CombineLatest2Signal<A, B, R>(a: _a, b: _b, resultSelector: compose(selector, _resultSelector))
    }
}

func compose<A, B, C>(f: B -> C, _ g: A -> B) -> A -> C { return { f(g($0)) } }
