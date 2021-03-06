/*
 * Copyright 2004-2018 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*

:record:`shared` (along with :record:`~OwnedObject.owned`) manage the
deallocation of a class instance. :record:`shared` is meant to be used when
many different references will exist to the object and these references need
to keep the object alive.

Using `shared`
--------------

To use :record:`shared`, allocate a class instance following this
pattern:

.. code-block:: chapel

 var mySharedObject = new shared MyClass(...));

When ``mySharedObject`` and any copies of it go out of scope, the class
instance it refers to will be deleted.

Copy initializing or assigning from mySharedObject will make
other variables refer to the same class instance. The class instance
will be deleted after all of these references go out of scope.

.. code-block:: chapel

 var globalSharedObject:shared MyClass;

 proc makeGlobalSharedObject() {
   var mySharedObject = new shared MyClass(...);
   globalSharedObject = mySharedObject;
   // the reference count is decremented when mySharedObject
   // goes out of scope. Since it's not zero after decrementing, the
   // MyClass instance is not deleted until globalSharedObject
   // goes out of scope.
 }

Borrowing from `shared`
-----------------------

The :proc:`shared.borrow` method returns the pointer managed by the
:record:`shared`. This pointer is only valid as long as the :record:`shared` is
storing that pointer. The compiler includes some checking for errors in this
case. In these ways, :record:`shared` is similar to
:record:`~OwnedObject.owned`.

See :ref:`about-owned-borrowing` for more details and examples.

Coercions for `shared`
----------------------

As with :record:`~OwnedObject.owned`, :record:`shared` supports
coercions to the class type as well as
coercions from a ``shared(T)`` to ``shared(U)`` where ``T`` is a
subclass of ``U``.

See :ref:`about-owned-coercions` for more details and examples.

`shared` Intents and Instantiation
----------------------------------

Intents and instantiation for :record:`shared` are similar
to :record:`~OwnedObject.owned`. Namely:

 * for formal arguments declared with a type, the
   default intent is `const in`, which updates the
   reference count and shares the instance.
 * for generic formal arguments with no type component that are
   passed actuals of :record:`shared` type,
   the formal argument will be instantiated with the borrow type,
   and no reference count changes will occur.

   .. note::

      It is expected that this rule will change in the future with
      more experience with this language design.


See also :ref:`about-owned-intents-and-instantiation` which includes examples.

 */
module SharedObject {

  use OwnedObject;

  // TODO unify with RefCountBase. Even though that one is for
  // intrusive ref-counting and this one isn't, there's no fundamental
  // reason it couldn't be one class.
  pragma "no doc"
  class ReferenceCount {
    var count: atomic int;

    // count should be initialized to 1 in default initializer.
    proc init() {
      // Want this:      count = 1;
      this.complete();
      count.write(1);
    }

    proc retain() {
      count.add(1);
    }
    proc release() {
      var oldValue = count.fetchSub(1);
      return oldValue - 1;
    }
  }


  /*

     :record:`shared` manages the deletion of a class instance in a way
     that supports multiple owners of the class instance.

     This is currently implemented with task-safe reference counting.

   */
  pragma "managed pointer"
  record _shared {
    pragma "no doc"
    type chpl_t;         // contained type (class type)

    pragma "no doc"
    pragma "owned"
    var chpl_p:chpl_t;   // contained pointer (class type)

    forwarding chpl_p;

    pragma "no doc"
    pragma "owned"
    var chpl_pn:unmanaged ReferenceCount; // reference counter

    /*
       Default-initialize a :record:`shared`.
     */
    proc init(type t) {
      if !isClass(t) then
        compilerError("shared only works with classes");

      this.chpl_t = _to_borrowed(t);
      this.chpl_p = nil;
      this.chpl_pn = nil;
    }

    pragma "no doc"
    proc init(p : borrowed) {
      compilerWarning("initializing shared from a borrow is deprecated");
      this.init(_to_unmanaged(p));
    }

    /*
       Initialize a :record:`shared` with a class instance.
       This :record:`shared` will take over the deletion of the class
       instance. It is an error to directly delete the class instance
       while it is managed by :record:`shared`.

       :arg p: the class instance to manage. Must be of unmanaged class type.
     */
    proc init(p : unmanaged) {
      this.chpl_t = _to_borrowed(p.type);

      // Boost version default-initializes px and pn
      // and then swaps in different values.

      var rc:unmanaged ReferenceCount = nil;

      if p != nil then
        rc = new unmanaged ReferenceCount();

      this.chpl_p = _to_borrowed(p);
      this.chpl_pn = rc;

      this.complete();

      // Boost includes a mechanism for classes inheriting from
      // enable_shared_from_this to record a weak pointer back to the
      // shared pointer. That would need to be handled in a Phase 2
      // since it would refer to `this` as a whole here.
    }

    proc init(p: ?T)
    where isClass(T) == false &&
          isSubtype(T, _shared) == false &&
          isIterator(p) == false {
      compilerError("shared only works with classes");
      this.chpl_t = T;
      this.chpl_p = p;
    }

    /*
       Initialize a :record:`shared` taking a pointer from
       a :record:`owned`.

       This :record:`shared` will take over the deletion of the class
       instance. It is an error to directly delete the class instance
       while it is managed by :record:`shared`.

       :arg take: the owned value to take ownership from
     */
    proc init(in take:owned) {
      var p = take.release();
      this.chpl_t = _to_borrowed(p.type);

      if !isClass(p) then
        compilerError("shared only works with classes");

      var rc:unmanaged ReferenceCount = nil;

      if p != nil then
        rc = new unmanaged ReferenceCount();

      this.chpl_p = p;
      this.chpl_pn = rc;

      this.complete();
    }

    /*
       Copy-initializer. Creates a new :record:`shared`
       that refers to the same class instance as `src`.
       These will share responsibility for managing the instance.
     */
    proc init(const ref src:_shared(?)) {
      this.chpl_t = src.chpl_t;
      this.chpl_p = src.chpl_p;
      this.chpl_pn = src.chpl_pn;

      this.complete();

      if this.chpl_pn != nil then
        this.chpl_pn.retain();
    }

    /*
       The deinitializer for :record:`shared` will destroy the class
       instance once there are no longer any copies of this
       :record:`shared` that refer to it.
     */
    proc deinit() {
      clear();
    }

    /*
       Change the instance managed by this class to `newPtr`.
       If this record was the last :record:`shared` managing a
       non-nil instance, that instance will be deleted.
     */
    proc ref retain(newPtr:unmanaged chpl_t) {
      clear();
      this.chpl_p = newPtr;
      if newPtr != nil {
        this.chpl_pn = new unmanaged ReferenceCount();
      }
    }

    /*
       Empty this :record:`shared` so that it stores `nil`.
       Deletes the managed object if this :record:`shared` is the
       last :record:`shared` managing that object.
       Does not return a value.

       Equivalent to ``shared.retain(nil)``.
     */
    proc ref clear() {
      if isClass(chpl_p) { // otherwise, let error happen on init call
        if chpl_p != nil && chpl_pn != nil {
          var count = chpl_pn.release();
          if count == 0 {
            delete _to_unmanaged(chpl_p);
            delete chpl_pn;
          }
        }
        chpl_p = nil;
        chpl_pn = nil;
      }
    }

    /*
       Return the object managed by this :record:`shared` without
       impacting its lifetime at all. It is an error to use the
       value returned by this function after the last :record:`shared`
       goes out of scope or deletes the contained class instance
       for another reason, including calls to
       `=`, or :proc:`retain` when this is the last :record:`shared`
       referring to the instance.
       In some cases such errors are caught at compile-time.
     */
    proc /*const*/ borrow() {
      return chpl_p;
    }

    // = should call retain-release
    // copy-init should call retain
  }


  /*
     Assign one :record:`shared` to another.
     Deletes the object managed by ``lhs`` if there are
     no other :record:`shared` referring to it. On return,
     ``lhs`` will refer to the same object as ``rhs``.
   */
  proc =(ref lhs:_shared, rhs: _shared) {
    // retain-release
    if rhs.chpl_pn != nil then
      rhs.chpl_pn.retain();
    lhs.clear();
    lhs.chpl_p = rhs.chpl_p;
    lhs.chpl_pn = rhs.chpl_pn;
  }

  /*
     Set a :record:`shared` from a :record:`~OwnedObject.owned`.
     Deletes the object managed by ``lhs`` if there are
     no other :record:`shared` referring to it.
     On return, ``lhs`` will refer to the object previously
     managed by ``rhs``, and ``rhs`` will refer to `nil`.
   */
  proc =(ref lhs:_shared, in rhs:owned) {
    lhs.retain(rhs.release());
  }

  pragma "no doc"
  proc =(ref lhs:shared, rhs:_nilType) {
    lhs.clear();
  }

  /*
     Swap two :record:`shared` objects.
   */
  proc <=>(ref lhs: _shared, ref rhs: _shared) {
    lhs.chpl_pn <=> rhs.chpl_pn;
    lhs.chpl_p <=> rhs.chpl_p;
  }

  // This is a workaround
  pragma "no doc"
  pragma "auto destroy fn"
  proc chpl__autoDestroy(x: _shared) {
    __primitive("call destructor", x);
  }

  // Don't print out 'chpl_p' when printing an Shared, just print class pointer
  pragma "no doc"
  proc _shared.readWriteThis(f) {
    f <~> this.chpl_p;
  }

  // Note, coercion from _shared -> _shared.chpl_t is sometimes directly
  // supported in the compiler via a call to borrow() and
  // sometimes uses this cast.
  pragma "no doc"
  inline proc _cast(type t, const ref x:_shared) where isSubtype(t,x.chpl_t) {
    return x.borrow();
  }

  // This cast supports coercion from Shared(SubClass) to Shared(ParentClass)
  // (i.e. when class SubClass : ParentClass ).
  // It only works in a value context (i.e. when the result of the
  // coercion is a value, not a reference).
  pragma "no doc"
  inline proc _cast(type t:_shared, in x:_shared)
  where isSubtype(x.chpl_t,t.chpl_t) {
    var ret:t; // default-init the Shared type to return
    ret.chpl_p = x.chpl_p:t.chpl_t; // cast the class type
    ret.chpl_pn = x.chpl_pn;
    // steal the reference count increment we did for 'in' intent
    x.chpl_p = nil;
    x.chpl_pn = nil;
    return ret;
  }

  // cast from nil to shared
  pragma "no doc"
  inline proc _cast(type t:_shared, x:_nilType) {
    var tmp:t;
    return tmp;
  }

  /* This type allows code using the pre-1.18 `Shared` record
     to continue to compile. It will be removed in a future release.
   */
  type Shared = _shared;
}
