#include "natalie.hpp"

namespace Natalie {

Value ProcObject::initialize(Env *env, Block *block) {
    m_block = block;
    return this;
}

Value ProcObject::call(Env *env, Args args, Block *block) {
    assert(m_block);
    if (is_lambda() && m_break_point != 0) {
        try {
            return NAT_RUN_BLOCK_WITHOUT_BREAK(env, m_block, args, block);
        } catch (ExceptionObject *exception) {
            if (exception->is_local_jump_error_with_break_point(m_break_point))
                return exception->send(env, "exit_value"_s);
            throw exception;
        }
    }
    return NAT_RUN_BLOCK_WITHOUT_BREAK(env, m_block, args, block);
}

bool ProcObject::equal_value(Value other) const {
    return other->is_proc() && other->as_proc()->m_block == m_block;
}

Value ProcObject::ruby2_keywords(Env *env) {
    auto block_wrapper = [](Env *env, Value self, Args args, Block *block) -> Value {
        auto kwargs = args.has_keyword_hash() ? args.pop_keyword_hash() : new HashObject;
        auto new_args = args.to_array_for_block(env, 0, -1, true);
        if (!kwargs->is_empty())
            new_args->push(HashObject::ruby2_keywords_hash(env, kwargs));
        auto old_block = env->outer()->var_get("old_block", 1)->as_proc();
        return old_block->call(env, new_args, block);
    };

    auto inner_env = new Env { *env };
    inner_env->var_set("old_block", 1, true, new ProcObject { m_block });
    m_block = new Block { inner_env, this, block_wrapper, -1 };

    return this;
}

Value ProcObject::source_location() {
    assert(m_block);
    auto file = m_block->env()->file();
    if (file == nullptr) return NilObject::the();
    return new ArrayObject { new StringObject { file }, Value::integer(static_cast<nat_int_t>(m_block->env()->line())) };
}

StringObject *ProcObject::to_s(Env *env) {
    assert(m_block);
    String suffix {};
    if (m_block->env()->file())
        suffix.append(String::format(" {}:{}", m_block->env()->file(), m_block->env()->line()));
    if (is_lambda() || m_block->is_from_method())
        suffix.append(" (lambda)");
    if (m_block->self()->is_symbol())
        suffix.append(String::format(" (&:{})", m_block->self()->as_symbol()->string()));
    auto str = String::format("#<{}:{}{}>", m_klass->inspect_str(), String::hex(object_id(), String::HexFormat::LowercaseAndPrefixed), suffix);
    return new StringObject { std::move(str), Encoding::ASCII_8BIT };
}

}
