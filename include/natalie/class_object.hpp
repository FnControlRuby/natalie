#pragma once

#include <assert.h>

#include "natalie/block.hpp"
#include "natalie/env.hpp"
#include "natalie/forward.hpp"
#include "natalie/global_env.hpp"
#include "natalie/macros.hpp"
#include "natalie/module_object.hpp"
#include "natalie/object.hpp"

namespace Natalie {

class ClassObject : public ModuleObject {
public:
    ClassObject()
        : ClassObject { GlobalEnv::the()->Class() } { }

    ClassObject(ClassObject *klass)
        : ModuleObject { Object::Type::Class, klass } { }

    ClassObject *subclass(Env *env, const char *name) {
        return subclass(env, name, m_object_type);
    }

    ClassObject *subclass(Env *env, const char *name, Type object_type) {
        return subclass(env, new String(name), object_type);
    }

    ClassObject *subclass(Env *env, const String *name = nullptr) {
        return subclass(env, name, m_object_type);
    }

    ClassObject *subclass(Env *, const String *, Type);

    static ClassObject *bootstrap_class_class(Env *);
    static ClassObject *bootstrap_basic_object(Env *, ClassObject *);

    Type object_type() { return m_object_type; }

    Value initialize(Env *, Value, Block *);

    static Value new_method(Env *env, Value superclass, Block *block) {
        if (superclass) {
            if (!superclass->is_class()) {
                env->raise("TypeError", "superclass must be a Class ({} given)", superclass->klass()->class_name_or_blank());
            }
        } else {
            superclass = GlobalEnv::the()->Object();
        }
        Value klass = superclass->as_class()->subclass(env);
        if (block) {
            block->set_self(klass);
            NAT_RUN_BLOCK_AND_POSSIBLY_BREAK(env, block, 0, nullptr, nullptr);
        }
        return klass;
    }

    bool is_singleton() const { return m_is_singleton; }
    void set_is_singleton(bool is_singleton) { m_is_singleton = is_singleton; }

    virtual void gc_inspect(char *buf, size_t len) const override {
        if (m_class_name)
            snprintf(buf, len, "<ClassObject %p name=%p>", this, m_class_name.value());
        else
            snprintf(buf, len, "<ClassObject %p name=(none)>", this);
    }

private:
    Type m_object_type { Type::Object };
    bool m_is_singleton { false };
};

}
